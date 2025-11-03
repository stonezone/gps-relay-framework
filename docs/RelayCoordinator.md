# RelayCoordinator Guide

The `LocationRelayCoordinator` wraps `LocationRelayService` plus one or more transports into a portable bundle you can drop into any host app. It is designed for scenarios like the **robot cameraman**: the Apple Watch tracks the subject, the iPhone relays fixes to a Jetson/Orin base station, and other projects can reuse the same streaming pipeline.

## When to use it

Use the coordinator when you want:

- A single entry point to start/stop GPS relaying.
- Battery-aware tracking presets without wiring UI in every host.
- WebSocket transport lifecycle management (including TLS enforcement) without duplicating boilerplate.
- Delegate callbacks you can fan out to hardware controllers, analytics, or custom UI.

If you need more control (e.g. injecting a custom BLE transport), you can still work directly with `LocationRelayService` and attach your transports manually.

## Quick Start (Robot Cameraman)

```swift
import LocationRelayService
import LocationCore

final class JetsonRelayController: LocationRelayCoordinatorDelegate {
    private let coordinator: LocationRelayCoordinator

    init() {
        let endpoint = LocationRelayCoordinator.Configuration.WebSocketEndpoint(
            url: URL(string: "wss://jetson.local:9443/relay")!,
            configuration: WebSocketTransportConfiguration(
                customHeaders: ["X-Device-ID": UIDevice.current.identifierForVendor?.uuidString ?? ""]
            )
        )

        coordinator = LocationRelayCoordinator(
            configuration: .init(
                trackingMode: .balanced,
                webSocketEndpoint: endpoint
            )
        )
        coordinator.delegate = self
    }

    func startRelay() {
        coordinator.start()
    }

    func stopRelay() {
        coordinator.stop()
    }

    // MARK: - LocationRelayCoordinatorDelegate

    func relayCoordinator(_ coordinator: LocationRelayCoordinator, didUpdate fix: LocationFix) {
        // Forward to Jetson control loop: combine with base-station GNSS + PTZ control
    }

    func relayCoordinator(_ coordinator: LocationRelayCoordinator, didChangeHealth health: RelayHealth) {
        // Update UI lights or log health metrics
    }

    func relayCoordinator(_ coordinator: LocationRelayCoordinator, didUpdateConnection state: ConnectionState) {
        // Monitor WebSocket connectivity
    }

    func relayCoordinator(_ coordinator: LocationRelayCoordinator, authorizationDidFail error: LocationRelayError) {
        // Surface guidance to the end-user (e.g. show settings prompt)
    }
}
```

### Notes for Jetson/Orin integration

- The coordinator always streams `LocationFix` values in the same JSON schema used by the existing WebSocket transport. Your Jetson service can decode them exactly as today.
- Tracking mode defaults to `.balanced`; switch to `.realtime` for high-motion sports (surfing, wing foiling) or `.powersaver` for slow telemetry.
- Health changes indicate whether the watch is providing fresh GPS. Fall back to the phone’s location when health becomes `.degraded`.

## Customising configuration

```swift
var config = LocationRelayCoordinator.Configuration()
config.trackingMode = .realtime
config.qualityOverride = QualityThresholds(
    maxHorizontalAccuracy: 25,
    maxAge: 4,
    maxSpeed: 100
)
config.additionalTransports = [MyCustomTransport()]

let coordinator = LocationRelayCoordinator(configuration: config)
```

If you need to swap transports mid-session, call `restart(with:)` with a new configuration. The coordinator tears down the existing service and reattaches transports.

## Error handling

- WebSocket validation enforces `wss://` by default; set `allowInsecureConnections` on `WebSocketTransportConfiguration` only for local development.
- `authorizationDidFail` forwards the same errors exposed by `LocationRelayService`, making it easy to surface permission issues in host UI.
- `didEncounterError` surfaces socket-level errors; reconnect logic still runs automatically when allowed.

## Testing tips

- Inject `MockLocationManager` (see `LocationRelayServiceTests`) to simulate fixes and authorisation states.
- Supply a custom `LocationTransport` stub in `additionalTransports` to assert data flow without hitting a live server.

## Next steps

- Add your Jetson control logic to respond to `LocationFix` updates and blend them with the base station’s GNSS/orientation.
- For projects that need persistence or GPX export, compose the coordinator with the upcoming persistence module—no changes to the host integration.
