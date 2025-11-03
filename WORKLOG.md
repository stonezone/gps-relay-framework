## 2025-02-15 – Session Start

- Created baseline commit `chore: snapshot before codex modifications` to capture pre-existing state.
- Drafted task list from CODEX_REVIEW findings to track remediation.

### TODO

- [x] Fix deployment targets (iOS/watchOS) and Swift tools version for Xcode 16 compatibility.
- [x] Add missing Info.plist keys (Bluetooth, ATS) for BLE/WebSocket support.
- [x] Repair `LocationRelayService` state handling (current fix storage, phone fallback lifecycle, initial health notification).
- [x] Harden `WebSocketTransport` send completion crash path.
- [x] Clean up watch temp files and update location authorization workflow.
- [x] Integrate `HKWorkoutSession` delegate + builder management.
- [x] Modernize watch UI navigation (NavigationStack) and document Jetson port usage.
- [x] Ensure tests compile under CI (re-home iOS-only suites) and update documentation.
- [x] Add fusion/prep layer or interim weighting strategy for Jetson accuracy improvements.

_Progress entries and remaining work will be appended as tasks complete._

## 2025-02-15 – Update 1

- Set deployment targets to iOS 18 / watchOS 11 in project and shared configs.
- Bumped Package.swift manifests to Swift tools 6.0 with matching platform floors.
- Added Bluetooth usage descriptions, ATS local-network exception, and BLE background modes to `iosTrackerApp/Info.plist`.
- Patched `LocationRelayService` to retain the latest fix, manage phone fallback lifecycle, and send initial delegate state.
- Fixed `WebSocketTransport` crash when the transport is deallocated during send completion.

### TODO

1. Document on-device validation steps for iOS/watchOS once hardware is available.
2. Capture follow-up item: extend fusion engine to ingest Jetson GNSS when upstream API is ready.

## 2025-02-15 – Update 2

- Extended fusion documentation (RelayCoordinator) and clarified BLE CBOR mapping.
- Refined watch workout lifecycle (HKWorkoutSession + HKLiveWorkoutBuilder delegates) and removed temp file leaks.
- Migrated watch UI to `NavigationStack` and corrected Jetson tethering docs/README ATS note.
- Implemented fused location weighting before publishing transports and verified with `swift build` / `swift test`.
