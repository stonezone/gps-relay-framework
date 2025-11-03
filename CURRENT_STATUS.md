# GPS Relay Framework – Current Status & Roadmap

_Last updated: 2025-11-02_

## Overview
The GPS Relay Framework is now positioned as a reusable Swift package that can embed into multiple host projects (e.g., robot cameraman). The architecture centers on `LocationRelayService`, a new coordinator façade, and modular transport layers. Sample iOS & watchOS apps showcase integration paths.

Key accomplishments to date:
- Coordinator façade (`LocationRelayCoordinator`) created, wiring relay service + transports with host-friendly delegates.
- Tracking modes, quality thresholds, and filtering live in the package (gated for Apple platforms) with UI controls in the sample app.
- Security hardening for WebSocket transport requiring `wss://` by default with optional opt-in to `ws://` for local development.
- iOS sample (`iosTrackerApp`) refactored to rely on the coordinator and surface configuration UIs (tracking modes, endpoint, connection state, alerts).
- watchOS companion build remains functional with watch-centric updates pending (future phases).
- Command-line builds succeed for both phone and watch hardware.

## Recent Work Summary
- `Sources/LocationRelayService/LocationRelayCoordinator.swift`: Added coordinator wrapper, delegate callbacks, watch connectivity forwarding, and WebSocket management.
- `Sources/WebSocketTransport/WebSocketTransport.swift`: Introduced scheme validation and `allowInsecureConnections` flag.
- `Sources/LocationCore/TrackingMode.swift`: Added iOS/watchOS-only tracking mode definitions.
- `iosTrackerAppPackage` updates: View model now coordinates via the new façade; `ContentView` surfaces more controls.
- `docs/RelayCoordinator.md`: Integration guide for host projects (e.g., Jetson).
- `xcodebuild` builds verified for `iosTrackerApp` (iPhone) and `watchTrackerApp Watch App` (Apple Watch).

## Current State
- **Framework**: Location manager protocol, tracking modes, quality filtering, authorization handling, and WebSocket security all implemented and validated via Swift package builds/tests.
- **Coordinator**: Available, documented, and used by sample apps; ready for host embedding.
- **Sample Apps**: iOS app runs on device with new UI; watch app builds/deploys using existing code.
- **Testing**: Swift package unit tests run (limited to macOS host). iOS/watch integration tests still outstanding.
- **Docs**: Research report (COMPREHENSIVE_RESEARCH_REPORT.md), TODO roadmap, and coordinator guide exist. A new status doc (this file) acts as a hand-off reference.
- **Warnings**: Xcode build warns about supported interface orientations (to address later).

## Roadmap

### Near Term (Week 1)
1. **Coordinate watch app updates**
   - Move watch feature set to use coordinator or equivalent abstraction.
   - Surface tracking mode selection (if applicable) and ensure HK integration hooks align with new patterns.
2. **Refine iOS sample UX**
   - Add metrics display (e.g., battery use estimates) and authorization prompt guidance.
   - Provide developer mode toggles for debug logging.
3. **Address orientation & App Store warnings**
   - Review deployment info to satisfy Apple’s orientation guideline or mark full-screen requirement.

### Mid Term (Weeks 2-3)
1. **HealthKit completion (watch)**
   - Implement `HKLiveWorkoutBuilder` + `HKWorkoutRouteBuilder` under optional feature flags.
   - Create configuration interface to enable/disable HealthKit integration.
2. **Persistence module (iOS)**
   - Separate Core Data persistence layer with CoreData-backed service + protocols for optional adoption.
   - Update coordinator configuration to plug in persistence/export functionality.
3. **Telemetry & Logging**
   - Add structured logging hooks for Jetson base to capture anomalies (battery drain, rejected fixes).

### Longer Term (Weeks 4+)
1. **GPX export & map visualization** (optional modules)
   - Provide CLI service and UI actions for data export.
2. **Testing & CI**
   - Expand unit/UI tests, set up GitHub Actions or Xcode Cloud pipeline to run builds/tests.
3. **Documentation**
   - Build developer onboarding guide (extends RelayCoordinator.md) including end-to-end deployment steps for phone + watch pair.

## Outstanding Follow-up
- Hook watch app logic into new shared abstractions (coordinator or similar).
- Validate real-device HealthKit behaviour once HK features are implemented.
- Run endurance/battery tests using new tracking modes and document metrics.
- Decide on final orientation / UI design direction to address Xcode warning.
- Formalize persistence/export modules as toggleable services.

Keep this file updated as milestones complete and new work is scoped.
