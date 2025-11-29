import Foundation
import LocationCore

#if canImport(WatchConnectivity)
import WatchConnectivity
import WebSocketTransport

@MainActor
public class WatchTransportManager: ObservableObject {
    private let wcSession = WCSession.default
    private var webSocket: WebSocketTransport?
    
    // CONFIGURATION: Replace with your actual Cloudflare Tunnel Endpoint
    private let jetsonPublicURL = URL(string: "wss://YOUR-CLOUDFLARE-URL.trycloudflare.com")!
    
    public init() {}
    
    public func send(_ fix: LocationFix) {
        // PRIORITY 1: Bluetooth (Power Efficient, Low Latency)
        if wcSession.isReachable {
            sendViaBluetooth(fix)
            return
        }
        
        // PRIORITY 2: LTE Direct (Bypasses Apple Cloud Relay)
        sendViaDirectSocket(fix)
    }
    
    private func sendViaBluetooth(_ fix: LocationFix) {
        // If we are back on Bluetooth, close the LTE socket to save data/battery
        if let ws = webSocket, ws.connectionState == .connected {
            ws.close()
            webSocket = nil
        }
        
        // Use standard WCSession (interactive message)
        guard let data = try? JSONEncoder().encode(fix) else { return }
        wcSession.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }
    
    private func sendViaDirectSocket(_ fix: LocationFix) {
        // Initialize socket if needed
        if webSocket == nil {
             var config = WebSocketTransportConfiguration()
             config.timeout = 5.0 // Fail fast if network is bad
             webSocket = WebSocketTransport(url: jetsonPublicURL, configuration: config)
             webSocket?.open()
        }
        
        // Wrap fix in RelayUpdate for compatibility with Jetson parser
        let update = RelayUpdate(remote: fix)
        webSocket?.push(update)
    }
}
#else

/// Fallback no-op implementation for platforms where WatchConnectivity
/// is unavailable (e.g., macOS unit tests).
@MainActor
public class WatchTransportManager: ObservableObject {
    public init() {}
    public func send(_ fix: LocationFix) {
        // No-op
    }
}

#endif

