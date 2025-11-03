import Foundation
#if canImport(LocationCore)
import LocationCore
#else
// Lightweight shims to allow compilation when LocationCore isn't available.
// These mirror only what's needed by LocationRelayService.
public struct LocationCoordinate: Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LocationSource: String, Codable {
    case iOS
    case watchOS
}

public struct LocationFix: Codable, Equatable {
    public var timestamp: Date
    public var source: LocationSource
    public var coordinate: LocationCoordinate
    public var altitudeMeters: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double
    public var speedMetersPerSecond: Double
    public var courseDegrees: Double
    public var headingDegrees: Double?
    public var batteryFraction: Double
    public var sequence: Int
    public init(timestamp: Date, source: LocationSource, coordinate: LocationCoordinate, altitudeMeters: Double?, horizontalAccuracyMeters: Double, verticalAccuracyMeters: Double, speedMetersPerSecond: Double, courseDegrees: Double, headingDegrees: Double?, batteryFraction: Double, sequence: Int) {
        self.timestamp = timestamp
        self.source = source
        self.coordinate = coordinate
        self.altitudeMeters = altitudeMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.speedMetersPerSecond = speedMetersPerSecond
        self.courseDegrees = courseDegrees
        self.headingDegrees = headingDegrees
        self.batteryFraction = batteryFraction
        self.sequence = sequence
    }
}

public enum RelayHealth: Equatable {
    case idle
    case streaming
    case degraded(reason: String)
}

public struct QualityThresholds: Equatable {
    public let maxHorizontalAccuracy: Double
    public let maxAge: TimeInterval
    public let maxSpeed: Double
}

public struct LocationConfig {
    public let desiredAccuracy: Double
    public let distanceFilter: Double
    public let estimatedBatteryUsePerHour: Double
    public let description: String
    public let qualityThresholds: QualityThresholds
}

public enum TrackingMode: String, CaseIterable {
    case realtime
    case balanced
    case powersaver
    case minimal

    public var configuration: LocationConfig {
        let thresholds = QualityThresholds(maxHorizontalAccuracy: 100, maxAge: 10, maxSpeed: 83.3)
        return LocationConfig(
            desiredAccuracy: 10,
            distanceFilter: 10,
            estimatedBatteryUsePerHour: 8,
            description: "",
            qualityThresholds: thresholds
        )
    }
}


public protocol LocationTransport {
    func open()
    func close()
    func push(_ fix: LocationFix)
}

public protocol LocationManagerProtocol: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var allowsBackgroundLocationUpdates: Bool { get set }
    @available(iOS 14.0, *)
    var authorizationStatus: CLAuthorizationStatus { get }

    func requestWhenInUseAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startUpdatingHeading()
    func stopUpdatingHeading()
}

extension CLLocationManager: LocationManagerProtocol {}
#endif

public enum LocationRelayError: Error, Equatable {
    case authorizationDenied
    case authorizationRestricted
    case locationServicesDisabled
    case accuracyReduced
}

extension LocationRelayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Location access denied. Enable in Settings > Privacy > Location Services."
        case .authorizationRestricted:
            return "Location access restricted. Check Screen Time or device management settings."
        case .locationServicesDisabled:
            return "Location Services disabled system-wide. Enable them in Settings."
        case .accuracyReduced:
            return "Precise location is disabled. Enable it in Settings for best tracking."
        }
    }
}

#if os(iOS)
import CoreLocation
import WatchConnectivity
import UIKit

public protocol LocationRelayDelegate: AnyObject {
    func didUpdate(_ fix: LocationFix)
    func healthDidChange(_ health: RelayHealth)
    func watchConnectionDidChange(_ isConnected: Bool)
    func authorizationDidFail(_ error: LocationRelayError)
}

public extension LocationRelayDelegate {
    func authorizationDidFail(_ error: LocationRelayError) {}
}


public final class LocationRelayService: NSObject, @unchecked Sendable {
    public weak var delegate: LocationRelayDelegate?

    private let locationManager: LocationManagerProtocol
    public var trackingMode: TrackingMode {
        didSet {
            guard oldValue != trackingMode else { return }
            applyTrackingMode()
        }
    }
    public var qualityOverride: QualityThresholds?
    public var effectiveQualityThresholds: QualityThresholds {
        activeQualityThresholds
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
    private var lastWatchFixDate: Date?
    private var currentHeading: CLHeading?  // Track latest compass heading
    private var transports: [LocationTransport] = []
    private var health: RelayHealth = .idle {
        didSet {
            guard oldValue != health else { return }
            let newHealth = health
            Task { @MainActor [weak self, newHealth] in
                guard let delegate = self?.delegate else { return }
                delegate.healthDidChange(newHealth)
            }
        }
    }
    private var isWatchConnected: Bool = false {
        didSet {
            guard oldValue != isWatchConnected else { return }
            let newState = isWatchConnected
            Task { @MainActor [weak self, newState] in
                guard let delegate = self?.delegate else { return }
                delegate.watchConnectionDidChange(newState)
            }
        }
    }
    private var watchSilenceTimer: Timer?
    private var isPhoneLocationActive = false
    private var canStartLocationAfterAuth = false
    private var backgroundActivitySession: AnyObject?

    private(set) var currentFix: LocationFix?

    private var activeQualityThresholds: QualityThresholds {
        qualityOverride ?? trackingMode.configuration.qualityThresholds
    }

    public init(locationManager: LocationManagerProtocol = CLLocationManager(),
                trackingMode: TrackingMode = .balanced) {
        self.locationManager = locationManager
        self.trackingMode = trackingMode
        super.init()
        locationManager.delegate = self
        applyTrackingMode()
        configureWatchSession()
        Task { @MainActor in
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluateWatchSilence()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchSilenceTimer = timer
    }

    public func start() {
        canStartLocationAfterAuth = true
        requestAuthorizations()
        transports.forEach { $0.open() }
    }

    public func stop() {
        stopPhoneLocation()
        transports.forEach { $0.close() }
        transports.removeAll()
        health = .idle
        watchSilenceTimer?.invalidate()
        watchSilenceTimer = nil
    }

    public func currentFixValue() -> LocationFix? {
        currentFix
    }

    public func addTransport(_ transport: LocationTransport) {
        transports.append(transport)
        transport.open()
    }

    private func requestAuthorizations() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Request authorization and rely on delegate callbacks to proceed.
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    private func configureWatchSession() {
        guard WCSession.isSupported() else {
            print("[LocationRelayService] WCSession not supported")
            return
        }
        print("[LocationRelayService] Activating WCSession")
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handleInboundFix(_ fix: LocationFix) {
        // Track watch fixes separately from phone fixes
        // Use reception time (Date()) instead of fix.timestamp to properly handle
        // delayed file transfers - we care about when we RECEIVED the data
        if fix.source == .watchOS {
            lastWatchFixDate = Date()
        }

        // Always push fixes to transports (both watch and phone)
        Task { @MainActor [weak self, fix] in
            guard let delegate = self?.delegate else { return }
            delegate.didUpdate(fix)
        }
        transports.forEach { $0.push(fix) }
        updateHealth()
    }

    private func updateHealth() {
        let now = Date()
        // Relay Health specifically tracks WATCH GPS data quality
        // Use 10 second window to avoid false "degraded" status due to timer timing jitter
        if let watchDate = lastWatchFixDate, now.timeIntervalSince(watchDate) <= 10 {
            health = .streaming
            return
        }

        // If watch isn't sending, check if we have permissions for fallback
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            status = locationManager.authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        if status == .denied || status == .restricted {
            health = .degraded(reason: "Location permission denied")
        } else if lastWatchFixDate == nil {
            health = .degraded(reason: "Awaiting watch GPS")
        } else {
            health = .degraded(reason: "Watch GPS not updating")
        }
    }

    private func evaluateWatchSilence() {
        let now = Date()
        // Use 10 second window to avoid false disconnection due to timer timing jitter
        if let watchDate = lastWatchFixDate, now.timeIntervalSince(watchDate) <= 10 {
            // Watch is actively sending data
            isWatchConnected = true
        } else {
            // Watch has stopped sending data or never sent any
            isWatchConnected = false
        }
        updateHealth()
    }

    private func applyTrackingMode() {
        let config = trackingMode.configuration
        locationManager.desiredAccuracy = config.desiredAccuracy
        locationManager.distanceFilter = config.distanceFilter
    }

    private func currentAuthorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    private func notifyAuthorizationFailure(_ error: LocationRelayError) {
        health = .degraded(reason: error.localizedDescription ?? "Authorization issue")
        Task { @MainActor [weak self, error] in
            self?.delegate?.authorizationDidFail(error)
        }
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    private func handleAuthorizationChange(status: CLAuthorizationStatus, accuracy: CLAccuracyAuthorization?) {
        // Ensure health reflects current state when authorization changes
        updateHealth()
        
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if #available(iOS 13.0, *) {
                locationManager.allowsBackgroundLocationUpdates = true
            }
            if #available(iOS 14.0, *), let accuracy, accuracy == .reducedAccuracy {
                notifyAuthorizationFailure(.accuracyReduced)
            } else {
                updateHealth()
            }
            if self.canStartLocationAfterAuth && CLLocationManager.locationServicesEnabled() {
                self.startPhoneLocation()
            }
        case .restricted:
            notifyAuthorizationFailure(.authorizationRestricted)
        case .denied:
            notifyAuthorizationFailure(.authorizationDenied)
        default:
            break
        }
    }

    private func shouldAccept(_ location: CLLocation) -> Bool {
        let thresholds = activeQualityThresholds
        // Reject invalid accuracy readings
        guard location.horizontalAccuracy >= 0 else { return false }
        guard location.horizontalAccuracy <= thresholds.maxHorizontalAccuracy else { return false }

        // Reject stale samples
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age <= thresholds.maxAge else { return false }

        // Reject teleportation-level speeds (if speed is valid)
        if location.speed >= 0 && location.speed > thresholds.maxSpeed {
            return false
        }

        return true
    }

    private func startPhoneLocation() {
        guard !isPhoneLocationActive else { return }
        isPhoneLocationActive = true
        if #available(iOS 15.0, *) {
            let session = CLBackgroundActivitySession()
            backgroundActivitySession = session
        }
        applyTrackingMode()
        locationManager.startUpdatingLocation()
        // Start heading updates to get compass direction
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }

    private func stopPhoneLocation() {
        guard isPhoneLocationActive else { return }
        isPhoneLocationActive = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        if #available(iOS 15.0, *), let session = backgroundActivitySession as? CLBackgroundActivitySession {
            session.invalidate()
        }
        backgroundActivitySession = nil
    }

    private func publishPhoneLocation(_ location: CLLocation) async {
        let batteryLevel = await MainActor.run {
            UIDevice.current.batteryLevel >= 0 ? Double(UIDevice.current.batteryLevel) : 0
        }
        
        let fix = LocationFix(
            timestamp: location.timestamp,
            source: .iOS,
            coordinate: .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            verticalAccuracyMeters: max(location.verticalAccuracy, 0),
            speedMetersPerSecond: max(location.speed, 0),
            courseDegrees: location.course >= 0 ? location.course : 0,
            headingDegrees: currentHeading?.magneticHeading.isNaN == false ? currentHeading?.magneticHeading : nil,
            batteryFraction: batteryLevel,
            sequence: Int(Int64(Date().timeIntervalSinceReferenceDate * 1000) % Int64(Int.max))
        )
        handleInboundFix(fix)
    }
}

extension LocationRelayService: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if #available(iOS 14.0, *) {
            handleAuthorizationChange(status: manager.authorizationStatus, accuracy: manager.accuracyAuthorization)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if #available(iOS 14.0, *) {
            handleAuthorizationChange(status: status, accuracy: manager.accuracyAuthorization)
        } else {
            handleAuthorizationChange(status: status, accuracy: nil)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

        guard let latest = locations.last else { return }
        guard shouldAccept(latest) else {
            #if DEBUG
            let thresholds = activeQualityThresholds
            print("[LocationRelayService] Rejected phone fix (accuracy=\(latest.horizontalAccuracy)m age=\(abs(latest.timestamp.timeIntervalSinceNow))s speed=\(latest.speed)) thresholds=\(thresholds)")
            #endif
            return
        }
        Task {
            await publishPhoneLocation(latest)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Store the latest heading for use when publishing location fixes
        currentHeading = newHeading
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        health = .degraded(reason: error.localizedDescription)
    }
}

extension LocationRelayService: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[LocationRelayService] WCSession activation completed with state: \(activationState.rawValue), reachable: \(session.isReachable), error: \(error?.localizedDescription ?? "none")")
        if let error {
            health = .degraded(reason: error.localizedDescription)
        }
        isWatchConnected = session.isReachable && activationState == .activated
        print("[LocationRelayService] isWatchConnected set to: \(isWatchConnected)")
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        // Called when the session can no longer be used to modify or add any new transfers
        // This occurs when the user switches to a different Apple Watch
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Called when all outstanding messages and transfers have been delivered
        // After this is called, we should reactivate the session for the new watch
        session.activate()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        isWatchConnected = session.isReachable && session.activationState == .activated
        updateHealth()
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("[LocationRelayService] Received application context update")
        isWatchConnected = true  // We just received context, so watch is connected
        guard let data = applicationContext["latestFix"] as? Data,
              let fix = try? decoder.decode(LocationFix.self, from: data) else {
            print("[LocationRelayService] Failed to decode fix from context")
            return
        }
        print("[LocationRelayService] Decoded context fix: lat=\(fix.coordinate.latitude), lon=\(fix.coordinate.longitude)")
        handleInboundFix(fix)
    }

    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        print("[LocationRelayService] Received message data: \(messageData.count) bytes")
        isWatchConnected = true  // We just received data, so watch is definitely connected
        guard let fix = try? decoder.decode(LocationFix.self, from: messageData) else {
            print("[LocationRelayService] Failed to decode LocationFix")
            return
        }
        print("[LocationRelayService] Decoded fix: lat=\(fix.coordinate.latitude), lon=\(fix.coordinate.longitude)")
        handleInboundFix(fix)
    }

    public func session(_ session: WCSession, didReceive file: WCSessionFile) {
        isWatchConnected = true  // We just received a file, so watch is connected
        guard let data = try? Data(contentsOf: file.fileURL), let fix = try? decoder.decode(LocationFix.self, from: data) else {
            return
        }
        handleInboundFix(fix)
    }
}
#else

public protocol LocationRelayDelegate: AnyObject {
    func didUpdate(_ fix: LocationFix)
    func healthDidChange(_ health: RelayHealth)
    func watchConnectionDidChange(_ isConnected: Bool)
    func authorizationDidFail(_ error: LocationRelayError)
}

public extension LocationRelayDelegate {
    func authorizationDidFail(_ error: LocationRelayError) {}
}

public final class LocationRelayService {
    public weak var delegate: LocationRelayDelegate?

    public init() {}

    public func start() {
        assertionFailure("LocationRelayService is iOS only")
    }

    public func stop() {}

    public func currentFixValue() -> LocationFix? { nil }

    public func addTransport(_ transport: LocationTransport) {
        transport.open()
    }
}
#endif



