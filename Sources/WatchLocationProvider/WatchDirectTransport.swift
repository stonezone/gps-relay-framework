import Foundation
import LocationCore

#if os(watchOS)

/// Direct WebSocket transport for Watch → Server communication when iPhone is not reachable.
/// This bypasses WCSession's iCloud relay to achieve lower latency over LTE.
@available(watchOS 6.0, *)
public final class WatchDirectTransport: NSObject, URLSessionWebSocketDelegate {

    // MARK: - Types

    public enum ConnectionState: String, Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed
    }

    public struct Configuration {
        /// Server URL for direct connection (wss://your-server/watch)
        public var serverURL: URL?

        /// Maximum reconnection attempts before giving up
        public var maxReconnectAttempts: Int = 5

        /// Initial backoff delay in seconds
        public var initialBackoffDelay: TimeInterval = 1.0

        /// Maximum backoff delay in seconds
        public var maxBackoffDelay: TimeInterval = 30.0

        /// Optional bearer token for authentication
        public var bearerToken: String?

        /// Device identifier to include in connection
        public var deviceId: String?

        public init() {}
    }

    // MARK: - Properties

    public var configuration: Configuration

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private let encoder = JSONEncoder()

    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                print("[WatchDirectTransport] State: \(oldValue) -> \(connectionState)")
                onStateChanged?(connectionState)
            }
        }
    }

    /// Callback when connection state changes
    public var onStateChanged: ((ConnectionState) -> Void)?

    /// Callback when an error occurs
    public var onError: ((Error) -> Void)?

    /// Current measured round-trip latency in milliseconds
    public private(set) var currentLatencyMs: Double = 0

    // Reconnection state
    private var reconnectAttempts: Int = 0
    private var reconnectTimer: Timer?
    private var shouldReconnect: Bool = false

    // Message queue for when disconnected (keep small for memory on Watch)
    private var messageQueue: [LocationFix] = []
    private let maxQueueSize = 20
    private let queueLock = NSLock()

    // Heartbeat
    private var heartbeatTimer: Timer?
    private var lastPongTime: Date?
    private var pendingHeartbeats: [String: Date] = [:]
    private let heartbeatInterval: TimeInterval = 10.0  // Less frequent on Watch to save battery
    private let heartbeatTimeout: TimeInterval = 30.0

    // MARK: - Initialization

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        super.init()

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 60
        // Allow cellular for direct LTE connection
        sessionConfig.allowsCellularAccess = true
        sessionConfig.waitsForConnectivity = true

        self.session = URLSession(
            configuration: sessionConfig,
            delegate: self,
            delegateQueue: .main
        )

        encoder.outputFormatting = .withoutEscapingSlashes
    }

    // MARK: - Public API

    /// Opens the direct WebSocket connection to the server
    public func open() {
        guard configuration.serverURL != nil else {
            print("[WatchDirectTransport] No server URL configured, cannot open")
            return
        }

        guard task == nil else {
            print("[WatchDirectTransport] Connection already exists")
            return
        }

        shouldReconnect = true
        reconnectAttempts = 0
        connect()
    }

    /// Pushes a location fix directly to the server
    public func push(_ fix: LocationFix) {
        guard let task = task, connectionState == .connected else {
            queueMessage(fix)
            return
        }

        sendFix(fix, via: task)
    }

    /// Closes the WebSocket connection
    public func close() {
        shouldReconnect = false
        cancelReconnectTimer()
        stopHeartbeat()

        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        connectionState = .disconnected

        queueLock.lock()
        messageQueue.removeAll()
        queueLock.unlock()
    }

    /// Check if we have a valid server URL configured
    public var isConfigured: Bool {
        return configuration.serverURL != nil
    }

    // MARK: - Private Methods - Connection

    private func connect() {
        guard let url = configuration.serverURL else { return }
        guard task == nil else { return }

        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting

        var request = URLRequest(url: url)

        // Add authentication if provided
        if let token = configuration.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add device identifier
        if let deviceId = configuration.deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        }

        // Identify as watch client
        request.setValue("watch", forHTTPHeaderField: "X-Client-Type")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        startReceiving()

        print("[WatchDirectTransport] Connecting to \(url.absoluteString) (attempt \(reconnectAttempts + 1))")
    }

    private func handleSuccessfulConnection() {
        connectionState = .connected
        reconnectAttempts = 0

        startHeartbeat()
        flushMessageQueue()
    }

    private func handleConnectionFailure(error: Error) {
        onError?(error)

        guard shouldReconnect else {
            connectionState = .disconnected
            return
        }

        if reconnectAttempts >= configuration.maxReconnectAttempts {
            print("[WatchDirectTransport] Max reconnection attempts reached")
            connectionState = .failed
            shouldReconnect = false
            return
        }

        let delay = calculateBackoffDelay()
        print("[WatchDirectTransport] Reconnecting in \(String(format: "%.1f", delay))s")

        connectionState = .reconnecting
        reconnectAttempts += 1

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.task = nil
            self?.connect()
        }
    }

    private func calculateBackoffDelay() -> TimeInterval {
        let exponent = min(reconnectAttempts, 4)
        let delay = configuration.initialBackoffDelay * pow(2.0, Double(exponent))
        return min(delay, configuration.maxBackoffDelay)
    }

    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - Private Methods - Messaging

    private func sendFix(_ fix: LocationFix, via task: URLSessionWebSocketTask) {
        do {
            // Wrap in a message envelope
            let message: [String: Any] = [
                "type": "location",
                "source": "watch",
                "fix": try JSONSerialization.jsonObject(with: encoder.encode(fix))
            ]
            let data = try JSONSerialization.data(withJSONObject: message)

            task.send(.data(data)) { [weak self] error in
                if let error = error {
                    print("[WatchDirectTransport] Send error: \(error.localizedDescription)")
                    self?.onError?(error)
                }
            }
        } catch {
            print("[WatchDirectTransport] Encode error: \(error.localizedDescription)")
            onError?(error)
        }
    }

    private func queueMessage(_ fix: LocationFix) {
        queueLock.lock()
        defer { queueLock.unlock() }

        if messageQueue.count >= maxQueueSize {
            // Remove oldest - for real-time tracking, newest matters most
            messageQueue.removeFirst()
        }

        messageQueue.append(fix)
    }

    private func flushMessageQueue() {
        queueLock.lock()
        // Send newest first
        let messages = Array(messageQueue.suffix(5).reversed())
        messageQueue.removeAll()
        queueLock.unlock()

        guard !messages.isEmpty, let task = task else { return }

        print("[WatchDirectTransport] Flushing \(messages.count) queued messages")
        for fix in messages {
            sendFix(fix, via: task)
        }
    }

    private func startReceiving() {
        task?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("[WatchDirectTransport] Receive error: \(error.localizedDescription)")
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self?.handleServerMessage(data)
                    }
                case .data(let data):
                    self?.handleServerMessage(data)
                @unknown default:
                    break
                }
            }
            self?.startReceiving()
        }
    }

    private func handleServerMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "pong":
            handleHeartbeatResponse(json)
        case "ack":
            // Server acknowledged receipt - could track for delivery confirmation
            break
        default:
            break
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        lastPongTime = Date()
        pendingHeartbeats.removeAll()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pendingHeartbeats.removeAll()
    }

    private func sendHeartbeat() {
        guard let task = task, connectionState == .connected else { return }

        // Check for timeout
        if let lastPong = lastPongTime, Date().timeIntervalSince(lastPong) > heartbeatTimeout {
            print("[WatchDirectTransport] Heartbeat timeout, reconnecting")
            task.cancel(with: .abnormalClosure, reason: nil)
            self.task = nil
            handleConnectionFailure(error: NSError(
                domain: "WatchDirectTransport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Heartbeat timeout"]
            ))
            return
        }

        let correlationId = UUID().uuidString.prefix(8).lowercased()
        let heartbeat: [String: Any] = [
            "type": "ping",
            "id": String(correlationId),
            "ts": Date().timeIntervalSince1970
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: heartbeat)
            pendingHeartbeats[String(correlationId)] = Date()

            task.send(.data(data)) { _ in }
        } catch {
            print("[WatchDirectTransport] Heartbeat encode error: \(error.localizedDescription)")
        }
    }

    private func handleHeartbeatResponse(_ json: [String: Any]) {
        guard let correlationId = json["id"] as? String else { return }

        lastPongTime = Date()

        if let sendTime = pendingHeartbeats.removeValue(forKey: correlationId) {
            let rtt = Date().timeIntervalSince(sendTime) * 1000
            currentLatencyMs = rtt
            print("[WatchDirectTransport] Heartbeat RTT: \(String(format: "%.0f", rtt))ms")
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[WatchDirectTransport] Connected")
        handleSuccessfulConnection()
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[WatchDirectTransport] Closed with code \(closeCode.rawValue)")
        task = nil

        if shouldReconnect {
            handleConnectionFailure(error: NSError(
                domain: "WatchDirectTransport",
                code: Int(closeCode.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Connection closed"]
            ))
        } else {
            connectionState = .disconnected
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[WatchDirectTransport] Task error: \(error.localizedDescription)")
            self.task = nil
            handleConnectionFailure(error: error)
        }
    }
}

#endif
