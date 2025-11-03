import Foundation
import LocationCore

#if os(watchOS)
import CoreLocation
import HealthKit
import WatchConnectivity
import WatchKit

public protocol WatchLocationProviderDelegate: AnyObject {
    func didProduce(_ fix: LocationFix)
    func didFail(_ error: Error)
}

/// Manages workout-driven location capture on watchOS and relays fixes to the phone.
public final class WatchLocationProvider: NSObject {
    public weak var delegate: WatchLocationProviderDelegate?

    private let workoutStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var workoutSession: HKWorkoutSession?
    private var wcSession: WCSession { WCSession.default }
    private let encoder = JSONEncoder()

    public override init() {
        super.init()
        locationManager.delegate = self
        encoder.outputFormatting = [.withoutEscapingSlashes]
    }

    public func startWorkoutAndStreaming(activity: HKWorkoutActivityType = .other) {
        requestAuthorizationsIfNeeded()
        startWorkoutSession(activity: activity)
        // Extended runtime session requires special entitlement - omitting for now
        // The workout session itself keeps the app active
        configureWatchConnectivity()

        // Configure for maximum update frequency
        locationManager.activityType = .other  // .other provides most frequent updates
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        // watchOS doesn't need allowsBackgroundLocationUpdates - the workout session handles this

        locationManager.startUpdatingLocation()
    }

    public func stop() {
        locationManager.stopUpdatingLocation()
        workoutSession?.end()
        workoutSession = nil
    }

    private func requestAuthorizationsIfNeeded() {
        var readTypes: Set<HKObjectType> = []
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) {
            readTypes.insert(heartRate)
        }
        workoutStore.requestAuthorization(toShare: [], read: readTypes) { _, _ in }

        // Request Always authorization for background location updates
        locationManager.requestAlwaysAuthorization()
    }

    private func startWorkoutSession(activity: HKWorkoutActivityType) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: workoutStore, configuration: configuration)
            session.startActivity(with: Date())
            workoutSession = session
        } catch {
            delegate?.didFail(error)
        }
    }

    private func configureWatchConnectivity() {
        if WCSession.isSupported() {
            print("[WatchLocationProvider] Activating WCSession")
            wcSession.delegate = self
            wcSession.activate()
        } else {
            print("[WatchLocationProvider] WCSession not supported")
        }
    }

    private func publishFix(_ fix: LocationFix) {
        delegate?.didProduce(fix)
        print("[WatchLocationProvider] Session state: \(wcSession.activationState.rawValue), reachable: \(wcSession.isReachable)")
        guard wcSession.activationState == .activated else {
            print("[WatchLocationProvider] Session not activated")
            return
        }

        // Always update application context for latest fix (works in background)
        updateApplicationContextWithFix(fix)

        // Try interactive messaging first if reachable
        if wcSession.isReachable {
            do {
                let data = try encoder.encode(fix)
                print("[WatchLocationProvider] Sending interactive message (\(data.count) bytes)")
                wcSession.sendMessageData(data, replyHandler: nil) { [weak self] error in
                    print("[WatchLocationProvider] Interactive send failed: \(error.localizedDescription), falling back to file transfer")
                    // Retry via background transfer on failure
                    self?.queueBackgroundTransfer(for: fix)
                }
            } catch {
                print("[WatchLocationProvider] Encode error: \(error.localizedDescription)")
                delegate?.didFail(error)
                queueBackgroundTransfer(for: fix)
            }
        } else {
            // Not reachable, use background transfer as backup
            print("[WatchLocationProvider] Not reachable, using file transfer")
            queueBackgroundTransfer(for: fix)
        }
    }

    private func updateApplicationContextWithFix(_ fix: LocationFix) {
        guard wcSession.activationState == .activated else { return }
        do {
            let data = try encoder.encode(fix)
            let context = ["latestFix": data]
            try wcSession.updateApplicationContext(context)
            print("[WatchLocationProvider] Updated application context with latest fix")
        } catch {
            print("[WatchLocationProvider] Failed to update context: \(error.localizedDescription)")
            // Non-fatal, other methods will still deliver
        }
    }

    private func queueBackgroundTransfer(for fix: LocationFix) {
        guard wcSession.activationState == .activated else { return }
        do {
            let data = try encoder.encode(fix)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try data.write(to: url)
            wcSession.transferFile(url, metadata: nil)
            print("[WatchLocationProvider] Queued file transfer")
        } catch {
            delegate?.didFail(error)
        }
    }
}

extension WatchLocationProvider: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let device = WKInterfaceDevice.current()
        let fix = LocationFix(
            timestamp: latest.timestamp,
            source: .watchOS,
            coordinate: .init(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude),
            altitudeMeters: latest.verticalAccuracy >= 0 ? latest.altitude : nil,
            horizontalAccuracyMeters: latest.horizontalAccuracy,
            verticalAccuracyMeters: max(latest.verticalAccuracy, 0),
            speedMetersPerSecond: max(latest.speed, 0),
            courseDegrees: latest.course >= 0 ? latest.course : 0,
            headingDegrees: nil,  // Apple Watch doesn't have compass
            batteryFraction: device.batteryLevel >= 0 ? Double(device.batteryLevel) : 0,
            sequence: Int(Int64(Date().timeIntervalSinceReferenceDate * 1000) % Int64(Int.max))
        )
        publishFix(fix)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        delegate?.didFail(error)
    }
}

extension WatchLocationProvider: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[WatchLocationProvider] WCSession activation completed with state: \(activationState.rawValue), error: \(error?.localizedDescription ?? "none")")
        if let error {
            delegate?.didFail(error)
        }
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        // Intentionally left blank; reachability is checked during send.
    }

#if os(watchOS)
    public func session(_ session: WCSession, didReceiveMessageData messageData: Data) {}
    public func session(_ session: WCSession, didReceive file: WCSessionFile) {}
#endif
}

#else

public protocol WatchLocationProviderDelegate: AnyObject {
    func didProduce(_ fix: LocationFix)
    func didFail(_ error: Error)
}

public final class WatchLocationProvider {
    public weak var delegate: WatchLocationProviderDelegate?

    public init() {}

    public func startWorkoutAndStreaming(activity: Int = 0) {
        assertionFailure("WatchLocationProvider is only available on watchOS")
    }

    public func stop() {}
}
#endif

