import SwiftUI
import HealthKit
import LocationCore
import WatchLocationProvider

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

        isTracking = false
        statusMessage = "Tracking stopped"
        workoutState = "Stopped"
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
