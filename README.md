# GPS Relay Framework

A Swift-based framework that turns an **iPhone into a stationary base station** and an **Apple Watch into a roaming tracker**. The phone captures its own GPS/heading, ingests watch fixes wherever the wearer roams, and relays **two distinct streams** to a tethered host (e.g., Jetson) over WebSocket for fusion with local sensors such as computer vision.

## Overview

This framework provides a complete solution for capturing GPS data from both Apple Watch and iPhone, maintaining the phone’s baseline position while forwarding remote watch updates in near real time. Fixes travel over WatchConnectivity and are relayed to external systems (like Jetson devices) via WebSocket with explicit separation between **base** and **remote** tracks.

**Current Version:** v1.0.2

## Features

### iPhone App (Base Station)
- ✅ Continuous GPS + heading capture for the tethered base
- ✅ **Real-time compass heading updates** (immediate rotation response)
- ✅ Receives watch fixes via WatchConnectivity (interactive + background paths)
- ✅ Maintains independent base/remote streams for downstream consumers
- ✅ **Optional WebSocket** with enable/disable toggle (disabled by default)
- ✅ Automatic retry and reconnection with exponential backoff
- ✅ **Comprehensive telemetry** (queue depth, drops, duplicates, connectivity events)
- ✅ **Health monitoring** (per-stream status, update rates, signal quality)
- ✅ Battery level monitoring
- ✅ Background location updates

### Apple Watch App (Remote Tracker)
- ✅ Workout-driven GPS tracking while roaming away from the phone
- ✅ High-frequency location updates with HealthKit integration
- ✅ WatchConnectivity messaging plus background transfer/ application-context delivery
- ✅ Battery level monitoring

### WebSocket Server (Python)
- ✅ AsyncIO-based WebSocket server
- ✅ JSON schema validation
- ✅ JSONL persistence to disk
- ✅ Error responses to clients

## Quick Start

```bash
# Clone the repository
git clone https://github.com/stonezone/gps-relay-framework.git
cd gps-relay-framework

# Open in Xcode
open iosTrackerApp.xcodeproj

# Install server dependencies
cd jetson
pip install websockets jsonschema

# Run server
python3 jetsrv.py
```

> **Note:** The iOS target includes an ATS exception scoped to `192.168.55.1` so tethered Jetson devices can accept `ws://` connections. Use `wss://` for any production deployment.

## Data Format

The relay surfaces **base** and **remote** fixes. A typical WebSocket payload:

```json
{
  "base": {
    "ts_unix_ms": 1730000000000,
    "source": "iOS",
    "lat": 21.650000,
    "lon": -158.055000,
    "heading_deg": 45.0,
    "battery_pct": 0.92
  },
  "remote": {
    "ts_unix_ms": 1730000000250,
    "source": "watchOS",
    "lat": 21.645123,
    "lon": -158.050456,
    "speed_mps": 1.2,
    "battery_pct": 0.78
  },
  "fused": null
}
```

## Architecture

### Dual-Stream Design
The framework maintains **two completely independent GPS streams**:

1. **Base Stream (iPhone)**: Stationary reference point
   - Continuous GPS with compass heading
   - Low-power hysteresis mode when stationary
   - Real-time heading updates on device rotation

2. **Remote Stream (Watch)**: Mobile tracker
   - Workout-driven GPS updates
   - Works in Bluetooth range (1-2 Hz) or LTE (0.06-0.2 Hz)
   - Application context + background file transfers for reliability

### Data Flow
```
Apple Watch → WatchConnectivity → iPhone → WebSocket → Jetson/Host
                                     ↓
                              Phone GPS + Heading
```

Both streams are sent as separate payloads in `RelayUpdate`:
```swift
struct RelayUpdate {
    var base: LocationFix?    // iPhone (base station)
    var remote: LocationFix?  // Watch (remote tracker)
    var fused: LocationFix?   // Optional (disabled by default)
}
```

## Testing & Quality

### Unit Tests (Phase 4.1)
- ✅ 81 total tests (32 comprehensive Phase 4 tests)
- ✅ Dual-stream simultaneous updates
- ✅ Retry queue failure scenarios
- ✅ Application context throttling
- ✅ Stream health monitoring
- ✅ Sequence gap detection

### Telemetry & Metrics (Phase 4.2)
```swift
let metrics = relayService.telemetrySnapshot()
// Returns: duplicates, drops, queue depth, peak queue, connectivity transitions
```

**Structured Logging:**
- `[CONNECTIVITY]` - Watch connect/disconnect events
- `[QUEUE]` - Message queue operations
- `[DROP]` - Message drops with reasons
- `[DEDUPE]` - Duplicate fix detection
- `[HEALTH]` - Stream health summaries

Run tests:
```bash
swift test --filter LocationRelayServiceTests
```

## Documentation

- **[Watch Deployment Guide](docs/watch-deployment.md)** - Physical device deployment, LTE behavior, operator guidance
- **[Relay Coordinator Guide](docs/RelayCoordinator.md)** - High-level coordinator API
- **[Jetson USB Tethering](docs/jetson-usb-tethering.md)** - iPhone-to-Jetson connectivity
- **[Phase 4 Test Report](PHASE4_TEST_REPORT.md)** - Comprehensive test coverage analysis

**Current Version:** v1.0.2

See full documentation in the repository.
