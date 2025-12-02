import Foundation
import WatchConnectivity
import WebSocketTransport
import LocationCore

@MainActor
public class WatchTransportManager: ObservableObject {
    private let wcSession = WCSession.default
    private var webSocket: WebSocketTransport?
    
    // ⚠️ TODO: Replace with your actual Cloudflare Tunnel URL
    private let jetsonPublicURL = URL(string: "wss://ws.stonezone.net")!
    
    public init() {}
    
    public func send(_ fix: LocationFix) {
        // Priority 1: Bluetooth (WCSession is reachable)
        if wcSession.isReachable {
            // Close LTE socket if open to save battery
            if let ws = webSocket, ws.connectionState == .connected {
                ws.close()
                webSocket = nil
            }
            // Send via Bluetooth
            guard let data = try? JSONEncoder().encode(fix) else { return }
            wcSession.sendMessageData(data, replyHandler: nil, errorHandler: nil)
        } else {
            // Priority 2: LTE Direct (WebSocket)
            if webSocket == nil {
                var config = WebSocketTransportConfiguration()
                config.sessionConfiguration.timeoutIntervalForRequest = 5.0
                config.sessionConfiguration.timeoutIntervalForResource = 5.0
                webSocket = WebSocketTransport(url: jetsonPublicURL, configuration: config)
                webSocket?.open()
            }
            let update = RelayUpdate(remote: fix)
            webSocket?.push(update)
        }
    }
}
