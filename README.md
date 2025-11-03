# GPS Relay Framework

A Swift-based framework that turns an **iPhone into a stationary base station** and an **Apple Watch into a roaming tracker**. The phone captures its own GPS/heading, ingests watch fixes wherever the wearer roams, and relays **two distinct streams** to a tethered host (e.g., Jetson) over WebSocket for fusion with local sensors such as computer vision.

## Overview

This framework provides a complete solution for capturing GPS data from both Apple Watch and iPhone, maintaining the phone’s baseline position while forwarding remote watch updates in near real time. Fixes travel over WatchConnectivity and are relayed to external systems (like Jetson devices) via WebSocket with explicit separation between **base** and **remote** tracks.

**Current Version:** v1.0.0

## Features

### iPhone App (Base Station)
- ✅ Continuous GPS + heading capture for the tethered base
- ✅ Receives watch fixes via WatchConnectivity (interactive + background paths)
- ✅ Maintains independent base/remote streams for downstream consumers
- ✅ WebSocket client for streaming data to external systems
- ✅ Automatic retry and reconnection
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

**Current Version:** v1.0.0

See full documentation in the repository.
