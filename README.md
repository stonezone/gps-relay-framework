# GPS Relay Framework

A Swift-based framework for relaying GPS location data between Apple Watch, iPhone, and external systems via WebSocket. Designed for real-time location tracking applications such as autonomous camera tracking, drone following, and other IoT projects.

## Overview

This framework provides a complete solution for capturing GPS data from both Apple Watch and iPhone, transmitting it in real-time over WatchConnectivity, and relaying it to external systems (like Jetson devices) via WebSocket.

**Current Version:** v1.0.0

## Features

### iPhone App
- ✅ Real-time GPS tracking with CoreLocation
- ✅ Magnetic compass heading (direction phone is pointing)
- ✅ Receives GPS data from Apple Watch via WatchConnectivity
- ✅ WebSocket client for streaming data to external systems
- ✅ Automatic retry and reconnection
- ✅ Battery level monitoring
- ✅ Background location updates

### Apple Watch App
- ✅ Workout-driven GPS tracking
- ✅ High-frequency location updates
- ✅ WatchConnectivity messaging to iPhone
- ✅ Fallback to file transfer when not reachable
- ✅ HealthKit integration
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

## Data Format

GPS fixes are transmitted as JSON:

```json
{
  "ts_unix_ms": 1730000000000,
  "source": "iOS",
  "lat": 21.645123,
  "lon": -158.050456,
  "alt_m": 10.5,
  "h_accuracy_m": 5.0,
  "v_accuracy_m": 8.0,
  "speed_mps": 1.2,
  "course_deg": 180.0,
  "heading_deg": 45.0,
  "battery_pct": 0.85,
  "seq": 12345
}
```

**Current Version:** v1.0.0

See full documentation in the repository.
