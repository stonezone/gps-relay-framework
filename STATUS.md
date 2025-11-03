# GPS Relay Framework – Status for Claude Code

_Last updated: 2025-11-03_

## Mission Snapshot
- **Primary goal**: Stationary iPhone base continuously streams its own GPS/heading while relaying near-real-time Apple Watch fixes as a second, distinct stream.
- **Architecture**: `LocationRelayService` publishes `RelayUpdate` structs (`base`, `remote`, optional `fused`). Transports (WebSocket/BLE) and the iOS UI consume both streams independently.

## Current Implementation Highlights
- **Dual streams active** (`Sources/LocationRelayService/LocationRelayService.swift:200-819`). Phone GPS stays on; watch fixes never fuse into a single payload.
- **Watch reliability**: WatchConnectivity messages retry with exponential backoff, staleness pruning, and deduplication; pending payloads flush when reachability returns.
- **Base station optimisation**: Phone speed samples feed a hysteresis-based low-power mode; heading updates restart when motion resumes.
- **Health visibility**: `streamHealthSnapshot()` exposes per-stream status for UI/telemetry; throttled logs surface degradations.
- **Watch app** (`Sources/WatchLocationProvider/WatchLocationProvider.swift`): application-context updates throttled (time + accuracy deltas) with metadata; background file transfers cleanly retried/cleaned.
- **Jetson server** (`jetson/jetsrv.py`): logs and disconnect summaries track iOS vs. watch fix counts separately.

## Outstanding Work (see `TODO.md:18-48`)
- **Phase 4** – Validation & Docs ✅ **COMPLETE**
  1. ✅ Added 32 comprehensive unit tests (81 total) for simultaneous phone/watch updates, retry queue failure scenarios, application-context throttling, and health logging.
  2. ✅ Expanded structured logging with `[CONNECTIVITY]`, `[QUEUE]`, `[DROP]`, `[DEDUPE]`, `[HEALTH]` prefixes and public telemetry API.
  3. ✅ Refreshed documentation (`docs/watch-deployment.md`, README) with LTE expectations, dual-stream schema, operator guidance.
- Deferred backlog: HealthKit workout routes, persistence, security hardening, battery benchmarking (keep on ice for future enhancement).

## Testing Notes
- `swift test` currently fails in this environment because SwiftPM cannot write to `~/.cache/clang` (sandbox restriction). When running locally, clear that path or run from Xcode where cache access is granted.
- No xcworkspace build was executed yet post-Phase 5; recommend `xcodebuild -workspace iosTrackerApp.xcworkspace -scheme iosTrackerApp -destination 'platform=iOS Simulator,name=iPhone 15'` (and equivalent watch target) once set up.

## Versioning Reminder
- Both apps display the version in the footer. Increment the patch number (`v1.0.x`) whenever shipping the next build. Add comments if further automation is needed.

## Quick Pointers
- Core logic for dual streams: `LocationRelayService.handleInboundFix` (~L348) and `streamHealthSnapshot` (~L752).
- Watch retry queue: same file (~L662-L749).
- Application-context throttling: `WatchLocationProvider.updateApplicationContextWithFix` (~L153-L187).
- Jetson logging separation: `jetson/jetsrv.py` (~L111-L168).

Use the TODO checklist to drive remaining work; Phase 4 is next on deck.
