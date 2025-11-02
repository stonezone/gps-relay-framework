# Test Plan

This plan mirrors the acceptance criteria from the hand-off summary and maps verification steps to each subsystem.

## Watch Path
- Start a one-hour outdoor workout via the watch app and confirm continuous GPS updates while the display is off.
- Toggle airplane mode on the watch to trigger `WCSession` reachability changes; ensure queued transfers flush when connectivity returns.

## iPhone Path
- Start the relay service with the watch streaming. Inspect delegate callbacks and verify fused updates are emitted.
- Disable the watch link (e.g. power off the watch); confirm the relay raises a degraded health signal and phone GPS takes over within 3 seconds.

## USB Transport
- On Jetson, ensure the USB tethered interface (usually `enx*`) obtains a DHCP lease (`ip addr`, `ip route`).
- From the iPhone, connect `WebSocketTransport` to `ws://<jetson-ip>:8080` and observe accepted connections in the server log.

## Resilience
- Unplug and replug the USB cable; expect the transport to reconnect without crashing the app.
- Force-quit the iOS app with "When In Use" permissions granted; confirm CLBackgroundActivitySession keeps the relay alive when relaunched in the background.

## Security
- Inject malformed JSON into the WebSocket server and confirm it is rejected without crashing.
- Rotate the bearer token (once implemented) and check that stale clients are dropped.
