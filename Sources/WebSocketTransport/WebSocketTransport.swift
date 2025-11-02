import Foundation
import LocationCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Connection State

/// Represents the current state of the WebSocket connection
public enum ConnectionState: String, CustomStringConvertible {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
    
    public var description: String {
        return rawValue
    }
}

// MARK: - Configuration

/// Configuration for WebSocket transport behavior
public struct WebSocketTransportConfiguration {
    /// Maximum number of reconnection attempts before giving up
    public var maxReconnectAttempts: Int
    
    /// Initial backoff delay in seconds
    public var initialBackoffDelay: TimeInterval
    
    /// Maximum backoff delay in seconds
    public var maxBackoffDelay: TimeInterval
    
    /// Maximum size of the message queue
    public var maxQueueSize: Int
    
    /// Custom HTTP headers to include in connection request
    public var customHeaders: [String: String]
    
    /// Bearer token for authentication (automatically adds Authorization header)
    public var bearerToken: String?
    
    /// Custom URLSessionConfiguration for advanced TLS settings
    public var sessionConfiguration: URLSessionConfiguration
    
    public init(
        maxReconnectAttempts: Int = 10,
        initialBackoffDelay: TimeInterval = 1.0,
        maxBackoffDelay: TimeInterval = 30.0,
        maxQueueSize: Int = 100,
        customHeaders: [String: String] = [:],
        bearerToken: String? = nil,
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.maxReconnectAttempts = maxReconnectAttempts
        self.initialBackoffDelay = initialBackoffDelay
        self.maxBackoffDelay = maxBackoffDelay
        self.maxQueueSize = maxQueueSize
        self.customHeaders = customHeaders
        self.bearerToken = bearerToken
        self.sessionConfiguration = sessionConfiguration
    }
}

// MARK: - Delegate Protocol

/// Delegate protocol for monitoring WebSocket connection health
@available(iOS 13.0, watchOS 6.0, macOS 10.15, *)
public protocol WebSocketTransportDelegate: AnyObject {
    /// Called when the connection state changes
    /// - Parameters:
    ///   - transport: The WebSocket transport instance
    ///   - state: The new connection state
    func webSocketTransport(_ transport: WebSocketTransport, didChangeState state: ConnectionState)
    
    /// Called when an error is encountered
    /// - Parameters:
    ///   - transport: The WebSocket transport instance
    ///   - error: The error that occurred
    func webSocketTransport(_ transport: WebSocketTransport, didEncounterError error: Error)
}

// MARK: - WebSocket Transport

@available(iOS 13.0, watchOS 6.0, macOS 10.15, *)
public final class WebSocketTransport: NSObject, LocationTransport, URLSessionWebSocketDelegate {
    // MARK: - Properties
    
    private let url: URL
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private let encoder = JSONEncoder()
    private let configuration: WebSocketTransportConfiguration
    
    /// Current connection state
    private(set) public var connectionState: ConnectionState = .disconnected {
        didSet {
            if oldValue != connectionState {
                NSLog("[WebSocketTransport] State changed: %@ -> %@", oldValue.description, connectionState.description)
                delegate?.webSocketTransport(self, didChangeState: connectionState)
            }
        }
    }
    
    /// Delegate for connection health monitoring
    public weak var delegate: WebSocketTransportDelegate?
    
    // Reconnection state
    private var reconnectAttempts: Int = 0
    private var reconnectTimer: Timer?
    private var shouldReconnect: Bool = false
    
    // Message queue for when disconnected
    private var messageQueue: [LocationFix] = []
    private let queueLock = NSLock()
    
    // MARK: - Initialization
    
    /// Initialize WebSocket transport with URL and optional configuration
    /// - Parameters:
    ///   - url: WebSocket server URL
    ///   - configuration: Transport configuration (uses defaults if not provided)
    public init(url: URL, configuration: WebSocketTransportConfiguration = WebSocketTransportConfiguration()) {
        self.url = url
        self.configuration = configuration
        super.init()
        
        // Configure session
        self.session = URLSession(
            configuration: configuration.sessionConfiguration,
            delegate: self,
            delegateQueue: .main
        )
        
        encoder.outputFormatting = .withoutEscapingSlashes
    }
    
    /// Legacy initializer for backward compatibility
    /// - Parameters:
    ///   - url: WebSocket server URL
    ///   - sessionConfiguration: URLSession configuration
    public convenience init(url: URL, sessionConfiguration: URLSessionConfiguration = .default) {
        var config = WebSocketTransportConfiguration()
        config.sessionConfiguration = sessionConfiguration
        self.init(url: url, configuration: config)
    }
    
    // MARK: - Public API
    
    /// Opens the WebSocket connection
    public func open() {
        guard task == nil else {
            NSLog("[WebSocketTransport] Connection already exists")
            return
        }
        
        shouldReconnect = true
        reconnectAttempts = 0
        connect()
    }
    
    /// Pushes a location fix to the server
    /// - Parameter fix: The location fix to send
    public func push(_ fix: LocationFix) {
        guard let task = task, connectionState == .connected else {
            // Queue message if not connected
            queueMessage(fix)
            return
        }
        
        sendMessage(fix, via: task)
    }
    
    /// Closes the WebSocket connection
    public func close() {
        shouldReconnect = false
        cancelReconnectTimer()
        
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        
        connectionState = .disconnected
        
        // Clear message queue
        queueLock.lock()
        messageQueue.removeAll()
        queueLock.unlock()
    }
    
    // MARK: - Private Methods - Connection Management
    
    private func connect() {
        guard task == nil else { return }
        
        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting
        
        // Create request with custom headers
        var request = URLRequest(url: url)
        
        // Add bearer token if provided
        if let bearerToken = configuration.bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Add custom headers
        for (key, value) in configuration.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Create and start WebSocket task
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receivePings()
        
        NSLog("[WebSocketTransport] Connecting to %@ (attempt %d)", url.absoluteString, reconnectAttempts + 1)
    }
    
    private func handleConnectionFailure(error: Error) {
        delegate?.webSocketTransport(self, didEncounterError: error)
        
        guard shouldReconnect else {
            connectionState = .disconnected
            return
        }
        
        if reconnectAttempts >= configuration.maxReconnectAttempts {
            NSLog("[WebSocketTransport] Max reconnection attempts (%d) reached", configuration.maxReconnectAttempts)
            connectionState = .failed
            shouldReconnect = false
            return
        }
        
        // Schedule reconnection with exponential backoff
        let backoffDelay = calculateBackoffDelay()
        NSLog("[WebSocketTransport] Scheduling reconnection in %.1f seconds", backoffDelay)
        
        connectionState = .reconnecting
        reconnectAttempts += 1
        
        reconnectTimer = Timer.scheduledTimer(
            withTimeInterval: backoffDelay,
            repeats: false
        ) { [weak self] _ in
            self?.connect()
        }
    }
    
    private func calculateBackoffDelay() -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
        let exponent = min(reconnectAttempts, 5) // Cap at 2^5 = 32
        let delay = configuration.initialBackoffDelay * pow(2.0, Double(exponent))
        return min(delay, configuration.maxBackoffDelay)
    }
    
    private func cancelReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    private func handleSuccessfulConnection() {
        connectionState = .connected
        reconnectAttempts = 0
        
        // Flush queued messages
        flushMessageQueue()
    }
    
    // MARK: - Private Methods - Message Handling
    
    private func sendMessage(_ fix: LocationFix, via task: URLSessionWebSocketTask) {
        do {
            let data = try encoder.encode(fix)
            task.send(.data(data)) { [weak self] error in
                if let error = error {
                    NSLog("[WebSocketTransport] Send error: %@", String(describing: error))
                    self?.delegate?.webSocketTransport(self!, didEncounterError: error)
                }
            }
        } catch {
            NSLog("[WebSocketTransport] Encoding error: %@", String(describing: error))
            delegate?.webSocketTransport(self, didEncounterError: error)
        }
    }
    
    private func queueMessage(_ fix: LocationFix) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Enforce queue size limit
        if messageQueue.count >= configuration.maxQueueSize {
            // Remove oldest message
            messageQueue.removeFirst()
            NSLog("[WebSocketTransport] Queue full, dropping oldest message")
        }
        
        messageQueue.append(fix)
        NSLog("[WebSocketTransport] Queued message (queue size: %d)", messageQueue.count)
    }
    
    private func flushMessageQueue() {
        queueLock.lock()
        let messagesToSend = messageQueue
        messageQueue.removeAll()
        queueLock.unlock()
        
        guard !messagesToSend.isEmpty, let task = task else { return }
        
        NSLog("[WebSocketTransport] Flushing %d queued messages", messagesToSend.count)
        
        for fix in messagesToSend {
            sendMessage(fix, via: task)
        }
    }
    
    private func receivePings() {
        guard let task = task else { return }
        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                NSLog("[WebSocketTransport] Receive error: %@", String(describing: error))
                self?.handleReceiveError(error)
            case .success(let message):
                // Log received message for debugging
                switch message {
                case .string(let text):
                    NSLog("[WebSocketTransport] Received text: %@", text)
                case .data(let data):
                    NSLog("[WebSocketTransport] Received data: %d bytes", data.count)
                @unknown default:
                    break
                }
            }
            self?.receivePings()
        }
    }
    
    private func handleReceiveError(_ error: Error) {
        delegate?.webSocketTransport(self, didEncounterError: error)
        
        // Connection likely closed, will be handled in didCompleteWithError
    }
    
    // MARK: - URLSessionWebSocketDelegate
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        NSLog("[WebSocketTransport] Connected to %@", webSocketTask.currentRequest?.url?.absoluteString ?? url.absoluteString)
        handleSuccessfulConnection()
    }
    
    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        NSLog("[WebSocketTransport] Closed with code %d, reason: %@", closeCode.rawValue, reasonString)
        
        task = nil
        
        if shouldReconnect {
            // Treat as connection failure and attempt reconnection
            let error = NSError(
                domain: "WebSocketTransport",
                code: Int(closeCode.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "WebSocket closed with code \(closeCode.rawValue)"]
            )
            handleConnectionFailure(error: error)
        } else {
            connectionState = .disconnected
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            NSLog("[WebSocketTransport] Task completed with error: %@", String(describing: error))
            self.task = nil
            handleConnectionFailure(error: error)
        } else {
            NSLog("[WebSocketTransport] Task completed cleanly")
            self.task = nil
            
            if shouldReconnect {
                // Unexpected clean completion, reconnect
                let error = NSError(
                    domain: "WebSocketTransport",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "WebSocket disconnected unexpectedly"]
                )
                handleConnectionFailure(error: error)
            } else {
                connectionState = .disconnected
            }
        }
    }
}
