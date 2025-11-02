import SwiftUI
import Combine
import LocationCore
import LocationRelayService
import WebSocketTransport

@MainActor
public class LocationRelayViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var isRelayActive: Bool = false
    @Published public var currentFix: LocationFix?
    @Published public var relayHealth: RelayHealth = .idle
    @Published public var webSocketURL: String = "ws://192.168.55.1:8765"
    @Published public var statusMessage: String = "Ready to start"
    @Published public var isWatchConnected: Bool = false
    @Published public var lastFixTimestamp: Date?

    // MARK: - Private Properties
    private let relayService: LocationRelayService
    private var webSocketTransport: WebSocketTransport?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    public init() {
        self.relayService = LocationRelayService()
        self.relayService.delegate = self
        setupObservers()
    }

    // MARK: - Public Methods
    public func startRelay() {
        guard !isRelayActive else { return }

        // Validate WebSocket URL
        guard let url = URL(string: webSocketURL),
              url.scheme == "ws" || url.scheme == "wss" else {
            statusMessage = "Invalid WebSocket URL"
            return
        }

        // Create and add WebSocket transport
        webSocketTransport = WebSocketTransport(url: url, sessionConfiguration: .default)
        if let transport = webSocketTransport {
            relayService.addTransport(transport)
        }

        // Start the relay service
        relayService.start()
        isRelayActive = true
        statusMessage = "Relay started"
    }

    public func stopRelay() {
        guard isRelayActive else { return }

        relayService.stop()

        // Close transport
        webSocketTransport?.close()
        webSocketTransport = nil

        isRelayActive = false
        statusMessage = "Relay stopped"
    }

    // MARK: - Private Methods
    private func setupObservers() {
        // Observe relay health changes
        NotificationCenter.default.publisher(for: NSNotification.Name("RelayHealthChanged"))
            .compactMap { $0.object as? RelayHealth }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] health in
                self?.relayHealth = health
            }
            .store(in: &cancellables)
    }

    private func updateStatusMessage() {
        switch relayHealth {
        case .idle:
            statusMessage = isRelayActive ? "Waiting for location..." : "Ready to start"
        case .streaming:
            statusMessage = "Streaming location data"
        case .degraded:
            statusMessage = "Connection degraded"
        }
    }
}

// MARK: - LocationRelayDelegate
extension LocationRelayViewModel: LocationRelayDelegate {
    nonisolated public func didUpdate(_ fix: LocationFix) {
        Task { @MainActor [fix] in
            self.currentFix = fix
            self.lastFixTimestamp = Date()
        }
    }

    nonisolated public func healthDidChange(_ health: RelayHealth) {
        Task { @MainActor [health] in
            self.relayHealth = health
            self.updateStatusMessage()
        }
    }

    nonisolated public func watchConnectionDidChange(_ isConnected: Bool) {
        Task { @MainActor [isConnected] in
            self.isWatchConnected = isConnected
        }
    }
}
