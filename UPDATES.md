# GPS Relay Framework – Remediation Plan

## Objective
Align the framework with the core requirement: a **stationary iPhone base station** must continuously stream its own position/heading while simultaneously relaying **real-time Apple Watch fixes** as a second, distinct stream for the tethered host device.

This document merges the validated items from `CRITICAL_CHANGES.md` and `EMERGENCY_CODEX.md`, adding clarifications uncovered during review.

---

## Highest-Priority Gaps (P0)

### 1. Dual Stream Separation
- **Issue**: `LocationRelayService` fuses watch + phone fixes (`Sources/LocationRelayService/LocationRelayService.swift:288-316`, `504-552`) and transports only the blended result.
- **Action**:
  1. Remove the unconditional call to `fusedLocation` inside `handleInboundFix`.
  2. Introduce a wrapper payload (e.g., `RelayUpdate { baseFix?, remoteFix?, fusedFix? }`).
  3. Deliver the wrapper to delegates, transports, and downstream UI so base/remote remain visible.
  4. Keep optional fusion logic behind an explicit mode flag (`RelayMode.mobileColocated`) for users that still need blended output.

### 2. Continuous Base Tracking
- **Issue**: Arrival of any watch fix triggers `stopPhoneLocation()` (`Sources/LocationRelayService/LocationRelayService.swift:288-339`), so the base stops reporting its own position.
- **Action**:
  1. Eliminate `stopPhoneLocation()` invocations tied to watch freshness.
  2. Ensure the phone continues periodic fixes (throttle if needed, but never stop automatically).
  3. Update health logic to track base and remote streams independently.
  4. Extend delegate/UI to surface base heading + fix age for operators.

### 3. WatchConnectivity Reliability over LTE
- **Issue**: Reliance on `WCSession.isReachable` → `sendMessageData` fails when the phone is locked or only reachable over cellular, forcing delayed `transferFile` batches and false “disconnected” states (`Sources/WatchLocationProvider/WatchLocationProvider.swift:82-117`, `Sources/LocationRelayService/LocationRelayService.swift:369-538`).
- **Action**:
  1. Add `updateApplicationContext` (or similar state channel) to push the latest fix regardless of reachability.
  2. Wrap `sendMessageData` with retry + background queue; dedupe fixes on the phone via sequence IDs.
  3. Base watch connection health on reception timestamps rather than `isReachable`; expose distinct statuses for interactive vs. background delivery.
  4. Clean up temp files after successful transfers to avoid storage creep.

---

## Supporting Changes (P1)

### 4. Transport & API Contract
- Update `LocationTransport` (and `WebSocketTransport`) to accept the new dual-stream payload. Provide a JSON structure with clear keys (`base`, `remote`, optional `fused`).
- Offer adapters for legacy single-fix consumers if required.
- Document the payload schema for the tethered host.

### 5. View Models & Sample UI
- `LocationRelayViewModel` and the iOS app should display both streams so operators can confirm the base remains stationary and the remote is moving.
- Consider exposing latency indicators (time since last fix) for both streams.

### 6. Domain Metadata (Optional)
- If keeping a single struct is preferred, add a `role` (base vs. remote) to `LocationFix`. Otherwise, rely on the wrapper/JSON keys above. Choose one path to avoid duplicating intent.

### 7. Testing & Telemetry
- Expand unit tests: simultaneous watch/phone updates, retry queue behaviour, application-context ingestion, and health transitions.
- Add logging for reachability state changes, retry attempts, and deduped fixes to aid field ops.

### 8. Documentation Refresh
- Update docs (`docs/watch-deployment.md`, README, status reports) with:
  - Expected LTE behaviour (interactive vs. background modes).
  - Dual-stream architecture and payload schema.
  - Operational guidance for mounting the base station and verifying alignment.

---

## Suggested Implementation Order
1. **Service refactor** – separate streams, keep phone GPS active, adjust delegate/interface.
2. **Watch connectivity resilience** – application context, retry/dedupe, health metrics, file cleanup.
3. **Transport & UI updates** – new payload handling, sample app visualization, schema docs.
4. **Testing & docs** – regression coverage and updated operations guidance.

---

## Validation Checklist
- Base fixes continue when watch fixes stream (`isPhoneLocationActive` remains true).
- Downstream transports receive explicit `base` and `remote` entries with accurate coordinates.
- Watch status stays “connected” during LTE sessions; latency stays within acceptable bounds.
- UI and logs confirm both streams’ freshness and heading values.

---

**Result:** Implementing the above restores compliance with the project goal: a dependable stationary base reporting its own state while relaying near-real-time remote tracker data.
