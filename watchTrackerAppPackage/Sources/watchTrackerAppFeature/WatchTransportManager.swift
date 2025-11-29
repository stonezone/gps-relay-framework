import Foundation
import WebSocketTransport
import LocationCore

#if os(watchOS)
import WatchConnectivity

/// Manages hybrid transport for Watch → Server communication.
/// Prioritizes Bluetooth (WCSession) when available, switches to Direct WebSocket (LTE)
/// when iPhone is not reachable. This bypasses Apple's iCloud relay for lower latency.
///
/// ## Configuration
/// Set `jetsonPublicURL` to your Cloudflare Tunnel endpoint before use:
/// ```swift
/// manager.jetsonPublicURL = URL(string: "wss://your-tunnel.trycloudflare.com")!
/// ```
@MainActor
public class WatchTransportManager: ObservableObject {
    private let wcSession = WCSession.default
    private var webSocket: WebSocketTransport?
    private let encoder = JSONEncoder()

    /// Cloudflare Tunnel endpoint for direct LTE connection.
    /// MUST be configured before using direct transport.
    /// Example: "wss://robot-cam.trycloudflare.com"
    public var jetsonPublicURL: URL?

    /// Optional bearer token for authentication
    public var bearerToken: String?

    /// Whether direct WebSocket transport is enabled (default: true)
    public var directTransportEnabled: Bool = true

    /// Connection state of direct transport
    @Published public var directConnectionState: ConnectionState = .disconnected

    /// Statistics
    @Published public private(set) var bluetoothSendCount: Int = 0
    @Published public private(set) var directSendCount: Int = 0

    public init() {
        encoder.outputFormatting = .withoutEscapingSlashes
    }

    /// Send a location fix via the best available transport.
    /// - Priority 1: Bluetooth (WCSession) - power efficient, low latency when near iPhone
    /// - Priority 2: Direct WebSocket (LTE) - bypasses iCloud relay when away from iPhone
    public func send(_ fix: LocationFix) {
        // PRIORITY 1: Bluetooth (Power Efficient, Low Latency)
        if wcSession.isReachable {
            sendViaBluetooth(fix)
            return
        }

        // PRIORITY 2: LTE Direct (Bypasses Apple Cloud Relay)
        if directTransportEnabled, jetsonPublicURL != nil {
            sendViaDirectSocket(fix)
        }
    }

    /// Close the direct WebSocket connection
    public func closeDirectConnection() {
        webSocket?.close()
        webSocket = nil
        directConnectionState = .disconnected
    }

    // MARK: - Private Methods

    private func sendViaBluetooth(_ fix: LocationFix) {
        // If we are back on Bluetooth, close the LTE socket to save data/battery
        if let ws = webSocket, ws.connectionState == .connected {
            print("[WatchTransportManager] Back on Bluetooth, closing LTE socket")
            ws.close()
            webSocket = nil
            directConnectionState = .disconnected
        }

        // Use standard WCSession (interactive message)
        guard let data = try? encoder.encode(fix) else {
            print("[WatchTransportManager] Failed to encode fix for Bluetooth")
            return
        }

        wcSession.sendMessageData(data, replyHandler: nil) { error in
            print("[WatchTransportManager] Bluetooth send failed: \(error.localizedDescription)")
        }

        bluetoothSendCount += 1
        print("[WatchTransportManager] Sent via Bluetooth (total: \(bluetoothSendCount))")
    }

    private func sendViaDirectSocket(_ fix: LocationFix) {
        guard let url = jetsonPublicURL else {
            print("[WatchTransportManager] Direct transport not configured - no URL set")
            return
        }

        // Initialize socket if needed
        if webSocket == nil {
            print("[WatchTransportManager] Initializing direct WebSocket to \(url.absoluteString)")

            var config = WebSocketTransportConfiguration()
            config.maxReconnectAttempts = 5
            config.initialBackoffDelay = 1.0
            config.maxBackoffDelay = 15.0

            if let token = bearerToken {
                config.bearerToken = token
            }

            webSocket = WebSocketTransport(url: url, configuration: config)
            webSocket?.delegate = WebSocketStateObserver(manager: self)
            webSocket?.open()
        }

        // Wrap fix in RelayUpdate for compatibility with Jetson parser
        let update = RelayUpdate(remote: fix)
        webSocket?.push(update)

        directSendCount += 1
        print("[WatchTransportManager] Sent via Direct LTE (total: \(directSendCount))")
    }
}

// MARK: - WebSocket State Observer

/// Observes WebSocket state changes and updates the manager
private class WebSocketStateObserver: WebSocketTransportDelegate {
    private weak var manager: WatchTransportManager?

    init(manager: WatchTransportManager) {
        self.manager = manager
    }

    func webSocketTransport(_ transport: WebSocketTransport, didChangeState state: ConnectionState) {
        Task { @MainActor [weak self] in
            self?.manager?.directConnectionState = state
            print("[WatchTransportManager] Direct transport state: \(state)")
        }
    }

    func webSocketTransport(_ transport: WebSocketTransport, didEncounterError error: Error) {
        print("[WatchTransportManager] Direct transport error: \(error.localizedDescription)")
    }
}

#else

// Stub for non-watchOS platforms (macOS, iOS)
@MainActor
public class WatchTransportManager: ObservableObject {
    public var jetsonPublicURL: URL?
    public var bearerToken: String?
    public var directTransportEnabled: Bool = true
    @Published public var directConnectionState: ConnectionState = .disconnected
    @Published public private(set) var bluetoothSendCount: Int = 0
    @Published public private(set) var directSendCount: Int = 0

    public init() {}

    public func send(_ fix: LocationFix) {
        // No-op on non-watchOS platforms
    }

    public func closeDirectConnection() {
        // No-op on non-watchOS platforms
    }
}

#endif
