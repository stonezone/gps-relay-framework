import SwiftUI
import LocationCore
import LocationRelayService
import WebSocketTransport

@MainActor
public final class LocationRelayViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published public private(set) var isRelayActive: Bool = false
    @Published public private(set) var currentFix: LocationFix?
    @Published public private(set) var relayHealth: RelayHealth = .idle
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    @Published public private(set) var isWatchConnected: Bool = false
    @Published public private(set) var lastFixTimestamp: Date?

    @Published public var webSocketURL: String {
        didSet {
            guard webSocketURL != oldValue else { return }
            UserDefaults.standard.set(webSocketURL, forKey: Defaults.webSocketURL)
        }
    }

    @Published public var trackingMode: TrackingMode {
        didSet {
            guard trackingMode != oldValue else { return }
            UserDefaults.standard.set(trackingMode.rawValue, forKey: Defaults.trackingMode)
            var updatedConfig = coordinator.configuration
            updatedConfig.trackingMode = trackingMode
            coordinator.configuration = updatedConfig
            updateStatusMessage()
        }
    }

    @Published public var allowInsecureConnections: Bool {
        didSet {
            guard allowInsecureConnections != oldValue else { return }
            UserDefaults.standard.set(allowInsecureConnections, forKey: Defaults.allowInsecureConnections)
        }
    }

    @Published public var statusMessage: String = "Ready to start"
    @Published public var authorizationMessage: String?

    // MARK: - Private Properties
    private let coordinator: LocationRelayCoordinator

    // MARK: - Initialization
    public init(coordinator: LocationRelayCoordinator? = nil) {
        let defaults = UserDefaults.standard
        let savedURL = defaults.string(forKey: Defaults.webSocketURL) ?? "ws://192.168.55.1:8765"
        let savedMode = defaults.string(forKey: Defaults.trackingMode).flatMap(TrackingMode.init(rawValue:)) ?? .balanced
        let savedAllow = defaults.object(forKey: Defaults.allowInsecureConnections) as? Bool ?? true

        self.webSocketURL = savedURL
        self.trackingMode = savedMode
        self.allowInsecureConnections = savedAllow

        let initialCoordinator = coordinator ?? LocationRelayCoordinator(configuration: .init(trackingMode: savedMode))
        self.coordinator = initialCoordinator

        self.coordinator.delegate = self
        self.coordinator.configuration.trackingMode = savedMode
        updateStatusMessage()
    }

    // MARK: - Public API

    public func startRelay() {
        guard !isRelayActive else { return }

        guard let url = URL(string: webSocketURL) else {
            statusMessage = "Invalid WebSocket URL"
            return
        }

        let scheme = url.scheme?.lowercased()
        if scheme != "ws" && scheme != "wss" {
            statusMessage = "URL must start with ws:// or wss://"
            return
        }

        if scheme == "ws" && !allowInsecureConnections {
            statusMessage = "Enable secure wss:// or allow insecure ws:// connections."
            return
        }

        var updatedConfig = coordinator.configuration
        let wsConfig = WebSocketTransportConfiguration(allowInsecureConnections: allowInsecureConnections)
        updatedConfig.webSocketEndpoint = .init(url: url, configuration: wsConfig)
        coordinator.configuration = updatedConfig

        coordinator.start()
        connectionState = coordinator.connectionState
        isRelayActive = true
        authorizationMessage = nil
        statusMessage = "Relay started"
    }

    public func stopRelay() {
        guard isRelayActive else { return }
        coordinator.stop()
        isRelayActive = false
        connectionState = .disconnected
        relayHealth = .idle
        isWatchConnected = false
        currentFix = nil
        statusMessage = "Relay stopped"
    }

    public func dismissAuthorizationMessage() {
        authorizationMessage = nil
    }

    // MARK: - Helpers

    private func updateStatusMessage() {
        if !isRelayActive {
            statusMessage = "Ready to start"
            return
        }

        switch relayHealth {
        case .idle:
            statusMessage = "Starting relay..."
        case .streaming:
            statusMessage = "Streaming location data"
        case .degraded(let reason):
            statusMessage = "Degraded: \(reason)"
        }
    }
}

// MARK: - Defaults Keys

private enum Defaults {
    static let webSocketURL = "relay.webSocketURL"
    static let trackingMode = "relay.trackingMode"
    static let allowInsecureConnections = "relay.allowInsecureConnections"
}

// MARK: - LocationRelayCoordinatorDelegate

@available(iOS 13.0, *)
extension LocationRelayViewModel: LocationRelayCoordinatorDelegate {
    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, didUpdate fix: LocationFix) {
        currentFix = fix
        lastFixTimestamp = Date()
    }

    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, didChangeHealth health: RelayHealth) {
        relayHealth = health
        updateStatusMessage()
    }

    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, didUpdateConnection state: ConnectionState) {
        connectionState = state
    }

    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, didEncounterError error: Error) {
        statusMessage = "Connection error: \(error.localizedDescription)"
    }

    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, authorizationDidFail error: LocationRelayError) {
        authorizationMessage = error.errorDescription ?? "Authorization issue."
        statusMessage = authorizationMessage ?? "Authorization issue."
    }

    public func relayCoordinator(_ coordinator: LocationRelayCoordinator, watchConnectionDidChange isConnected: Bool) {
        isWatchConnected = isConnected
    }
}
