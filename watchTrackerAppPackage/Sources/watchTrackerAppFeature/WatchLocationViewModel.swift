import SwiftUI
import HealthKit
import LocationCore
import WatchLocationProvider
import WebSocketTransport

@MainActor
public class WatchLocationViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var isTracking: Bool = false
    @Published public var currentFix: LocationFix?
    @Published public var lastFixTimestamp: Date?
    @Published public var statusMessage: String = "Ready to start"
    @Published public var workoutState: String = "Not started"
    @Published public var fixCount: Int = 0

    // MARK: - Private Properties
    private let locationProvider: WatchLocationProvider
    private let transportManager = WatchTransportManager()

    // MARK: - Initialization
    public init() {
        self.locationProvider = WatchLocationProvider()
        self.locationProvider.delegate = self
    }

    /// Configure direct WebSocket transport for LTE bypass.
    /// Call this before startTracking() with your Cloudflare Tunnel URL.
    /// - Parameters:
    ///   - url: Cloudflare Tunnel endpoint (e.g., wss://robot-cam.trycloudflare.com)
    ///   - bearerToken: Optional authentication token
    public func configureDirectTransport(url: URL, bearerToken: String? = nil) {
        transportManager.jetsonPublicURL = url
        transportManager.bearerToken = bearerToken
    }

    /// Enable or disable direct WebSocket transport
    public func setDirectTransportEnabled(_ enabled: Bool) {
        transportManager.directTransportEnabled = enabled
    }

    /// Current direct transport connection state
    public var directConnectionState: ConnectionState {
        transportManager.directConnectionState
    }

    /// Transport statistics
    public var bluetoothSendCount: Int { transportManager.bluetoothSendCount }
    public var directSendCount: Int { transportManager.directSendCount }

    // MARK: - Public Methods
    public func startTracking() {
        guard !isTracking else { return }

        locationProvider.startWorkoutAndStreaming()

        isTracking = true
        statusMessage = "Tracking started"
        workoutState = "Active"
    }

    public func stopTracking() {
        guard isTracking else { return }

        locationProvider.stop()
        transportManager.closeDirectConnection()

        isTracking = false
        statusMessage = "Tracking stopped"
        workoutState = "Stopped"

        // Log transport statistics
        print("[WatchLocationViewModel] Session stats - Bluetooth: \(bluetoothSendCount), Direct LTE: \(directSendCount)")
    }

    // MARK: - Private Methods
    private func updateStatusMessage() {
        if isTracking {
            statusMessage = "Fixes sent: \(fixCount)"
        } else {
            statusMessage = "Ready to start"
        }
    }
}

// MARK: - WatchLocationProviderDelegate
extension WatchLocationViewModel: WatchLocationProviderDelegate {
    nonisolated public func didProduce(_ fix: LocationFix) {
        Task { @MainActor [fix] in
            self.currentFix = fix
            self.lastFixTimestamp = Date()
            self.fixCount += 1
            self.updateStatusMessage()

            // Send to Jetson via best available transport (Bluetooth or Direct LTE)
            self.transportManager.send(fix)
        }
    }

    nonisolated public func didFail(_ error: Error) {
        Task { @MainActor in
            self.statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}
