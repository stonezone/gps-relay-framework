import Foundation
import LocationCore

// MARK: - Enhanced WebSocket Transport with Active Heartbeat

/// Protocol message types for the enhanced transport
public enum TransportMessageType: String, Codable, Sendable {
    case relayUpdate = "relay_update"
    case heartbeatPing = "heartbeat_ping"
    case heartbeatPong = "heartbeat_pong"
    case ack = "ack"
    case nack = "nack"
}

/// Wrapper for all transport messages
public struct TransportMessage: Codable, Sendable {
    public let type: TransportMessageType
    public let timestamp: Date
    public let correlationId: UUID?
    public let sequence: Int?
    public let payload: Data?
    
    public init(
        type: TransportMessageType,
        correlationId: UUID? = nil,
        sequence: Int? = nil,
        payload: Data? = nil
    ) {
        self.type = type
        self.timestamp = Date()
        self.correlationId = correlationId
        self.sequence = sequence
        self.payload = payload
    }
}

/// Enhanced WebSocket configuration with heartbeat settings
public struct EnhancedWebSocketConfiguration: Sendable {
    public var baseConfig: WebSocketTransportConfiguration
    
    /// Enable application-level heartbeat
    public var heartbeatEnabled: Bool
    
    /// Heartbeat interval in seconds
    public var heartbeatInterval: TimeInterval
    
    /// Heartbeat timeout in seconds
    public var heartbeatTimeout: TimeInterval
    
    /// Maximum missed heartbeats before declaring connection dead
    public var maxMissedHeartbeats: Int
    
    /// Enable message acknowledgment
    public var ackEnabled: Bool
    
    /// Acknowledgment timeout in seconds
    public var ackTimeout: TimeInterval
    
    /// Maximum unacknowledged messages before blocking
    public var maxUnackedMessages: Int
    
    public init(
        baseConfig: WebSocketTransportConfiguration = WebSocketTransportConfiguration(),
        heartbeatEnabled: Bool = true,
        heartbeatInterval: TimeInterval = 5.0,
        heartbeatTimeout: TimeInterval = 15.0,
        maxMissedHeartbeats: Int = 3,
        ackEnabled: Bool = false,
        ackTimeout: TimeInterval = 5.0,
        maxUnackedMessages: Int = 10
    ) {
        self.baseConfig = baseConfig
        self.heartbeatEnabled = heartbeatEnabled
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.maxMissedHeartbeats = maxMissedHeartbeats
        self.ackEnabled = ackEnabled
        self.ackTimeout = ackTimeout
        self.maxUnackedMessages = maxUnackedMessages
    }
}

/// Enhanced connection state with additional health information
public enum EnhancedConnectionState: Sendable {
    case disconnected
    case connecting
    case connected(health: ConnectionHealthInfo)
    case reconnecting(attempt: Int)
    case failed(reason: String)
    
    public struct ConnectionHealthInfo: Sendable {
        public let rttMs: Double?
        public let missedHeartbeats: Int
        public let unackedMessages: Int
        public let lastActivityAge: TimeInterval
    }
}

/// Delegate for enhanced transport events
@available(iOS 13.0, watchOS 6.0, macOS 10.15, *)
public protocol EnhancedWebSocketTransportDelegate: AnyObject {
    func transport(_ transport: EnhancedWebSocketTransport, didChangeState state: EnhancedConnectionState)
    func transport(_ transport: EnhancedWebSocketTransport, didReceiveGimbalTarget target: GimbalTarget)
    func transport(_ transport: EnhancedWebSocketTransport, didEncounterError error: Error)
    func transport(_ transport: EnhancedWebSocketTransport, didMeasureRTT rttMs: Double)
}

/// Enhanced WebSocket transport with active heartbeat and connection quality tracking
@available(iOS 13.0, watchOS 6.0, macOS 10.15, *)
public final class EnhancedWebSocketTransport: NSObject, LocationTransport, URLSessionWebSocketDelegate {
    
    // MARK: - Properties
    
    private let url: URL
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let configuration: EnhancedWebSocketConfiguration
    
    public weak var delegate: EnhancedWebSocketTransportDelegate?
    
    // Connection state
    private(set) public var state: EnhancedConnectionState = .disconnected {
        didSet {
            delegate?.transport(self, didChangeState: state)
        }
    }
    
    // Heartbeat
    private var heartbeatTimer: Timer?
    private var pendingHeartbeats: [UUID: Date] = [:]
    private var missedHeartbeatCount: Int = 0
    private var lastRTT: TimeInterval?
    private var rttSamples: [Double] = []
    
    // Acknowledgment tracking
    private var pendingAcks: [UUID: (message: RelayUpdate, sentAt: Date)] = [:]
    private var messageSequence: Int = 0
    
    // Reconnection
    private var reconnectAttempts: Int = 0
    private var reconnectTimer: Timer?
    private var shouldReconnect: Bool = false
    
    // Message queue
    private var messageQueue: [RelayUpdate] = []
    private let queueLock = NSLock()
    
    // Quality tracking
    public let qualityTracker = ConnectionQualityTracker()
    
    // MARK: - Initialization
    
    public init(url: URL, configuration: EnhancedWebSocketConfiguration = EnhancedWebSocketConfiguration()) {
        self.url = url
        self.configuration = configuration
        super.init()
        
        self.session = URLSession(
            configuration: configuration.baseConfig.sessionConfiguration,
            delegate: self,
            delegateQueue: .main
        )
        
        encoder.outputFormatting = .withoutEscapingSlashes
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }
    
    // MARK: - LocationTransport
    
    public func open() {
        guard task == nil else { return }
        
        shouldReconnect = true
        reconnectAttempts = 0
        connect()
    }
    
    public func push(_ update: RelayUpdate) {
        guard let task = task, isConnected else {
            queueMessage(update)
            return
        }
        
        sendRelayUpdate(update, via: task)
    }
    
    public func close() {
        shouldReconnect = false
        stopHeartbeat()
        cancelReconnectTimer()
        
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        
        state = .disconnected
        
        queueLock.lock()
        messageQueue.removeAll()
        queueLock.unlock()
    }
    
    // MARK: - Private - Connection
    
    private var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }
    
    private func connect() {
        guard task == nil else { return }
        
        state = reconnectAttempts > 0 ? .reconnecting(attempt: reconnectAttempts + 1) : .connecting
        
        guard validateURL() else { return }
        
        var request = URLRequest(url: url)
        
        if let token = configuration.baseConfig.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        for (key, value) in configuration.baseConfig.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        
        startReceiving()
        
        NSLog("[EnhancedWSTransport] Connecting to %@ (attempt %d)", url.absoluteString, reconnectAttempts + 1)
    }
    
    private func validateURL() -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            reportError("Missing URL scheme")
            return false
        }
        
        switch scheme {
        case "wss":
            return true
        case "ws":
            if configuration.baseConfig.allowInsecureConnections {
                NSLog("[EnhancedWSTransport] ⚠️ Using insecure ws:// connection")
                return true
            } else {
                reportError("Insecure ws:// disabled. Set allowInsecureConnections for dev.")
                return false
            }
        default:
            reportError("Unsupported scheme: \(scheme)")
            return false
        }
    }
    
    private func reportError(_ message: String) {
        let error = NSError(
            domain: "EnhancedWebSocketTransport",
            code: -1000,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        delegate?.transport(self, didEncounterError: error)
        state = .failed(reason: message)
        shouldReconnect = false
    }
    
    private func handleConnectionSuccess() {
        reconnectAttempts = 0
        missedHeartbeatCount = 0
        pendingHeartbeats.removeAll()
        pendingAcks.removeAll()
        
        updateConnectedState()
        
        if configuration.heartbeatEnabled {
            startHeartbeat()
        }
        
        flushMessageQueue()
    }
    
    private func handleConnectionFailure(error: Error) {
        delegate?.transport(self, didEncounterError: error)
        stopHeartbeat()
        
        guard shouldReconnect else {
            state = .disconnected
            return
        }
        
        if reconnectAttempts >= configuration.baseConfig.maxReconnectAttempts {
            state = .failed(reason: "Max reconnection attempts reached")
            shouldReconnect = false
            return
        }
        
        let backoff = calculateBackoff()
        state = .reconnecting(attempt: reconnectAttempts + 1)
        reconnectAttempts += 1
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: backoff, repeats: false) { [weak self] _ in
            self?.task = nil
            self?.connect()
        }
    }
    
    private func calculateBackoff() -> TimeInterval {
        let exponent = min(reconnectAttempts, 5)
        let delay = configuration.baseConfig.initialBackoffDelay * pow(2.0, Double(exponent))
        return min(delay, configuration.baseConfig.maxBackoffDelay)
    }
    
    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - Private - Heartbeat
    
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendHeartbeat()
        }
        
        // Send first heartbeat immediately
        sendHeartbeat()
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        pendingHeartbeats.removeAll()
    }
    
    private func sendHeartbeat() {
        guard let task = task, isConnected else { return }
        
        // Check for timed out heartbeats
        let now = Date()
        let timedOut = pendingHeartbeats.filter {
            now.timeIntervalSince($0.value) > configuration.heartbeatTimeout
        }
        
        for (id, _) in timedOut {
            pendingHeartbeats.removeValue(forKey: id)
            missedHeartbeatCount += 1
            NSLog("[EnhancedWSTransport] Heartbeat timeout (missed: %d)", missedHeartbeatCount)
        }
        
        // Check if connection is dead
        if missedHeartbeatCount >= configuration.maxMissedHeartbeats {
            NSLog("[EnhancedWSTransport] Connection dead - %d missed heartbeats", missedHeartbeatCount)
            task.cancel(with: .abnormalClosure, reason: "Heartbeat timeout".data(using: .utf8))
            return
        }
        
        // Send new heartbeat
        let correlationId = UUID()
        let message = TransportMessage(
            type: .heartbeatPing,
            correlationId: correlationId,
            sequence: nil,
            payload: nil
        )
        
        do {
            let data = try encoder.encode(message)
            pendingHeartbeats[correlationId] = now
            
            task.send(.data(data)) { [weak self] error in
                if let error = error {
                    NSLog("[EnhancedWSTransport] Heartbeat send error: %@", error.localizedDescription)
                }
            }
        } catch {
            NSLog("[EnhancedWSTransport] Heartbeat encode error: %@", error.localizedDescription)
        }
        
        updateConnectedState()
    }
    
    private func handleHeartbeatPong(correlationId: UUID) {
        guard let sentAt = pendingHeartbeats.removeValue(forKey: correlationId) else { return }
        
        let rtt = Date().timeIntervalSince(sentAt)
        lastRTT = rtt
        
        rttSamples.append(rtt * 1000)
        if rttSamples.count > 20 {
            rttSamples.removeFirst()
        }
        
        // Reset missed count on successful pong
        if missedHeartbeatCount > 0 {
            missedHeartbeatCount = 0
        }
        
        qualityTracker.recordMessage(sequence: -1, latencyMs: rtt * 1000)
        delegate?.transport(self, didMeasureRTT: rtt * 1000)
        
        updateConnectedState()
    }
    
    // MARK: - Private - Message Handling
    
    private func sendRelayUpdate(_ update: RelayUpdate, via task: URLSessionWebSocketTask) {
        do {
            let payload = try encoder.encode(update)
            
            messageSequence += 1
            let message = TransportMessage(
                type: .relayUpdate,
                correlationId: configuration.ackEnabled ? UUID() : nil,
                sequence: messageSequence,
                payload: payload
            )
            
            if configuration.ackEnabled, let correlationId = message.correlationId {
                pendingAcks[correlationId] = (update, Date())
            }
            
            let data = try encoder.encode(message)
            task.send(.data(data)) { [weak self] error in
                if let error = error {
                    self?.delegate?.transport(self!, didEncounterError: error)
                }
            }
            
            qualityTracker.expectSequence(messageSequence)
            
        } catch {
            delegate?.transport(self, didEncounterError: error)
        }
    }
    
    private func queueMessage(_ update: RelayUpdate) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        if messageQueue.count >= configuration.baseConfig.maxQueueSize {
            messageQueue.removeFirst()
        }
        
        messageQueue.append(update)
    }
    
    private func flushMessageQueue() {
        queueLock.lock()
        let messages = messageQueue
        messageQueue.removeAll()
        queueLock.unlock()
        
        guard let task = task else { return }
        
        for update in messages {
            sendRelayUpdate(update, via: task)
        }
    }
    
    private func startReceiving() {
        guard let task = task else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                NSLog("[EnhancedWSTransport] Receive error: %@", error.localizedDescription)
                // Connection will be handled in didCompleteWithError
                
            case .success(let message):
                self.handleReceivedMessage(message)
            }
            
            self.startReceiving()
        }
    }
    
    private func handleReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d):
            data = d
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        @unknown default:
            return
        }
        
        // Try to decode as TransportMessage first
        if let transportMsg = try? decoder.decode(TransportMessage.self, from: data) {
            handleTransportMessage(transportMsg)
            return
        }
        
        // Try to decode as gimbal target (legacy format)
        if let gimbalData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = gimbalData["type"] as? String,
           type == "gimbal_target" {
            handleGimbalTarget(gimbalData)
            return
        }
        
        NSLog("[EnhancedWSTransport] Unknown message format")
    }
    
    private func handleTransportMessage(_ message: TransportMessage) {
        switch message.type {
        case .heartbeatPong:
            if let correlationId = message.correlationId {
                handleHeartbeatPong(correlationId: correlationId)
            }
            
        case .heartbeatPing:
            // Respond with pong
            sendHeartbeatPong(correlationId: message.correlationId)
            
        case .ack:
            if let correlationId = message.correlationId {
                pendingAcks.removeValue(forKey: correlationId)
            }
            
        case .nack:
            if let correlationId = message.correlationId,
               let pending = pendingAcks.removeValue(forKey: correlationId) {
                // Re-queue for retry
                queueMessage(pending.message)
            }
            
        case .relayUpdate:
            // Server shouldn't send relay updates to client
            break
        }
    }
    
    private func sendHeartbeatPong(correlationId: UUID?) {
        guard let task = task, let correlationId = correlationId else { return }
        
        let message = TransportMessage(
            type: .heartbeatPong,
            correlationId: correlationId,
            sequence: nil,
            payload: nil
        )
        
        do {
            let data = try encoder.encode(message)
            task.send(.data(data)) { _ in }
        } catch {
            // Ignore pong send errors
        }
    }
    
    private func handleGimbalTarget(_ data: [String: Any]) {
        guard let pan = data["pan"] as? Double,
              let tilt = data["tilt"] as? Double,
              let distance = data["distance"] as? Double else { return }
        
        let confidence = data["confidence"] as? Double ?? 1.0
        let isPredicted = data["predicted"] as? Bool ?? false
        
        let target = GimbalTarget(
            panDegrees: pan,
            tiltDegrees: tilt,
            distanceMeters: distance,
            confidence: confidence,
            timestamp: Date()
        )
        
        delegate?.transport(self, didReceiveGimbalTarget: target)
    }
    
    private func updateConnectedState() {
        let health = EnhancedConnectionState.ConnectionHealthInfo(
            rttMs: rttSamples.isEmpty ? nil : rttSamples.reduce(0, +) / Double(rttSamples.count),
            missedHeartbeats: missedHeartbeatCount,
            unackedMessages: pendingAcks.count,
            lastActivityAge: 0  // TODO: Track actual activity
        )
        state = .connected(health: health)
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        NSLog("[EnhancedWSTransport] Connected")
        handleConnectionSuccess()
    }
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        NSLog("[EnhancedWSTransport] Closed: code=%d reason=%@", closeCode.rawValue, reasonStr)
        
        task = nil
        
        if shouldReconnect {
            let error = NSError(
                domain: "EnhancedWebSocketTransport",
                code: Int(closeCode.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Closed with code \(closeCode.rawValue)"]
            )
            handleConnectionFailure(error: error)
        } else {
            state = .disconnected
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("[EnhancedWSTransport] Task error: %@", error.localizedDescription)
            self.task = nil
            handleConnectionFailure(error: error)
        } else {
            self.task = nil
            if shouldReconnect {
                let error = NSError(
                    domain: "EnhancedWebSocketTransport",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected disconnect"]
                )
                handleConnectionFailure(error: error)
            } else {
                state = .disconnected
            }
        }
    }
}
