# GPS Relay Framework

[![Platform](https://img.shields.io/badge/platform-iOS%2018.0%2B%20%7C%20watchOS%2011.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.4-blue.svg)](https://github.com/stonezone/gps-relay-framework/releases)

A high-performance Swift framework for **real-time GPS tracking** with Apple Watch and iPhone. Captures GPS location from Apple Watch (worn by remote subject) and streams it to iPhone for display, processing, or relay to external systems.

## ✨ Key Features

- 🎯 **Real-Time GPS Tracking** - 0.5s throttle achieves ~2Hz updates from Apple Watch
- 📡 **WatchConnectivity Integration** - Triple-path messaging (interactive + context + file transfer)
- 🔋 **Battery Optimized** - Workout sessions keep GPS active while managing power consumption
- 📊 **Comprehensive Telemetry** - Queue depth, drops, duplicates, connectivity monitoring
- 🏥 **Health Monitoring** - Stream health, update rates, signal quality tracking
- 🔄 **Automatic Retry Logic** - Exponential backoff with queue management for offline periods
- 🧪 **Well Tested** - 81+ unit tests with 80%+ code coverage

## 📱 Use Cases

- **Pet Tracking**: Attach Apple Watch to pet collar, track real-time location on iPhone
- **Child/Elder Safety**: Monitor family members with live GPS updates
- **Outdoor Activities**: Track hiking companions, skiing buddies, or running partners
- **Asset Tracking**: Monitor vehicles, equipment, or valuable items
- **External Relay**: Optional WebSocket streaming to external systems (Jetson, servers, etc.)

## 🚀 Quick Start

### Prerequisites

- iOS 18.0+ (iPhone)
- watchOS 11.0+ (Apple Watch Series 4+)
- Xcode 16.0+
- Swift 6.0+

### Installation

```bash
# Clone the repository
git clone https://github.com/stonezone/gps-relay-framework.git
cd gps-relay-framework

# Open in Xcode
open iosTrackerApp.xcworkspace
```

### Basic Usage

**Watch App (GPS Capture):**
```swift
import WatchLocationProvider

let provider = WatchLocationProvider()
provider.startTracking()

// GPS fixes automatically sent to iPhone via WatchConnectivity
```

**iPhone App (GPS Display):**
```swift
import LocationRelayService

let relay = LocationRelayService()
relay.delegate = self
relay.startRelay()

// Receive GPS updates from watch
func relayService(_ service: LocationRelayService, didReceiveUpdate update: RelayUpdate) {
    if let remoteFix = update.remote {
        print("Watch location: \(remoteFix.coordinate.latitude), \(remoteFix.coordinate.longitude)")
        print("Accuracy: ±\(remoteFix.horizontalAccuracyMeters)m")
    }
}
```

## 🏗️ Architecture

### Core Components

1. **WatchLocationProvider** - Captures GPS on Apple Watch
   - HealthKit workout session for background GPS
   - 0.5s application context throttle (real-time updates)
   - Battery and accuracy monitoring

2. **LocationRelayService** - Coordinates GPS streams on iPhone
   - Receives watch fixes via WatchConnectivity
   - Optional iPhone base station GPS
   - Manages message queues and retry logic
   - Provides telemetry and health monitoring

3. **LocationCore** - Shared data models
   - `LocationFix` - GPS coordinate with metadata
   - `RelayUpdate` - Container for base/remote/fused streams
   - JSON serialization for external relay

### Data Flow

```
┌─────────────────┐
│  Apple Watch    │
│  (GPS Capture)  │
└────────┬────────┘
         │ WatchConnectivity
         │ • sendMessageData (Bluetooth: ~1-2Hz)
         │ • updateApplicationContext (Background)
         │ • transferFile (Guaranteed delivery)
         ↓
┌─────────────────┐
│  iPhone App     │
│  (Processing)   │
└────────┬────────┘
         │ Optional
         │ WebSocket
         ↓
┌─────────────────┐
│ External System │
│ (Jetson/Server) │
└─────────────────┘
```

### Performance

| Metric | Target | Achieved |
|--------|--------|----------|
| **GPS Update Rate** | ~2Hz (0.5s) | ✅ ~1-2Hz in Bluetooth |
| **LTE Latency** | <1 second | ✅ <1 second |
| **Sequence Gaps** | ≤1 (95%+) | ✅ 95%+ consecutive |
| **Battery Life (Watch)** | 8+ hours | ✅ 8-10 hours |
| **Test Coverage** | >80% | ✅ 81+ tests |

## 📡 LTE/Cellular Deployment

When the Apple Watch is **out of Bluetooth range** from the iPhone, it uses cellular (LTE) to communicate. This section covers the networking requirements for real-time tracking over LTE.

### The Challenge

The Watch cannot reach private IP addresses (e.g., `192.168.x.x`) over LTE. You need one of these deployment strategies:

### Option A: USB Tethering (Recommended for Robot Cameraman)

Connect iPhone directly to Jetson via USB cable.

```
┌─────────────┐  Bluetooth   ┌─────────────┐    USB     ┌─────────────┐
│ Apple Watch │ ───────────▶ │   iPhone    │ ─────────▶ │   Jetson    │
│  (Subject)  │  (~200ms)    │   (Base)    │  (~10ms)   │   (Robot)   │
└─────────────┘              └─────────────┘            └─────────────┘
       │                                                       ▲
       │            Direct WebSocket (LTE)                     │
       └───────────────────────────────────────────────────────┘
                        (When out of Bluetooth range)
```

**Setup:**
1. Enable **Personal Hotspot** on iPhone
2. Connect iPhone to Jetson via USB
3. Jetson sees iPhone as network interface (`usb0` or `eth1`)
4. iPhone gateway IP: `172.20.10.1` (constant)

```bash
# On Jetson - verify USB tethering
ip addr  # Look for 172.20.10.x interface

# Install drivers if needed
sudo apt-get install ipheth-utils libimobiledevice-utils usbmuxd
```

**Latency:** <300ms (Bluetooth) | 2-10s (LTE via Apple Cloud relay)

### Option B: Cloudflare Tunnel (Remote LTE Access)

Expose your Jetson to the internet via secure tunnel. Watch connects directly over LTE.

```
┌─────────────┐              ┌─────────────┐              ┌─────────────┐
│ Apple Watch │ ──────────▶  │  Cloudflare │  ─────────▶  │   Jetson    │
│    (LTE)    │   ~100ms     │    Edge     │   Tunnel     │  (Server)   │
└─────────────┘              └─────────────┘              └─────────────┘
```

**Setup on Jetson:**
```bash
# Install cloudflared
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install cloudflared

# Start tunnel (for testing - gives temporary URL)
cloudflared tunnel --url http://localhost:8765

# Output: https://random-name.trycloudflare.com
```

**Configure Watch App:**
```swift
// In your Watch app
provider.configureDirectTransport(
    serverURL: URL(string: "wss://your-tunnel.trycloudflare.com")!,
    bearerToken: "optional-auth-token"
)
provider.startWorkoutAndStreaming()
```

**Latency:** ~100-200ms (consistent over LTE)

### Option C: Bluetooth Only (Close Range)

Keep subject within Bluetooth range (~30m) of iPhone.

**Latency:** ~50-200ms (best case)

### Transport Priority

The framework automatically selects the best available transport:

| Priority | Transport | Latency | When Used |
|----------|-----------|---------|-----------|
| 1 | Bluetooth (`sendMessageData`) | 50-200ms | Watch near iPhone |
| 2 | Direct WebSocket (LTE) | 100-500ms | Configured + iPhone not reachable |
| 3 | File Transfer (iCloud) | 1-5s | Fallback, reliable but slow |
| 4 | Application Context | Throttled | Snapshot backup only |

### Configuring Direct Transport

```swift
import WatchLocationProvider

let provider = WatchLocationProvider()

// Configure direct WebSocket for LTE bypass
provider.configureDirectTransport(
    serverURL: URL(string: "wss://your-server.com/watch")!,
    bearerToken: "your-auth-token",  // Optional
    deviceId: "watch-001"            // Optional
)

// Enable/disable direct transport
provider.setDirectTransportEnabled(true)

// Start tracking - will automatically use best available transport
provider.startWorkoutAndStreaming(activity: .other)
```

### Monitoring Transport Usage

```swift
// After session ends, check transport statistics
print("Bluetooth sends: \(provider.bluetoothSendCount)")
print("Direct LTE sends: \(provider.directLTESendCount)")
print("File transfers: \(provider.fileTransferSendCount)")
```

## 📦 Project Structure

```
gps-relay-framework/
├── Sources/
│   ├── LocationCore/              # Shared data models
│   ├── WatchLocationProvider/     # Apple Watch GPS capture
│   └── LocationRelayService/      # iPhone coordination & relay
├── iosTrackerAppPackage/          # iOS app implementation
├── watchTrackerAppPackage/        # Watch app implementation
├── Tests/                         # Unit tests (81+ tests)
├── docs/                          # Documentation
│   ├── watch-deployment.md        # Deployment guide
│   ├── test-plan.md              # Testing guide
│   └── PROJECT_ALIGNMENT.md       # Vision & roadmap
├── Config/                        # Build configuration
└── Package.swift                  # Swift Package Manager manifest
```

## 🧪 Testing

Run the full test suite:

```bash
# All tests
swift test

# Specific test suite
swift test --filter LocationRelayServiceTests

# With code coverage
swift test --enable-code-coverage
```

### Test Coverage

- **LocationCore**: 100% (data models, serialization)
- **WatchLocationProvider**: 85% (GPS capture, WatchConnectivity)
- **LocationRelayService**: 80% (relay coordination, retry logic)

## 📚 Documentation

- **[Watch Deployment Guide](docs/watch-deployment.md)** - Deploy to physical Apple Watch, LTE behavior
- **[Test Plan](docs/test-plan.md)** - Testing procedures and validation
- **[Project Alignment](docs/PROJECT_ALIGNMENT.md)** - Vision, goals, and roadmap
- **[Version Bumping](docs/VERSION_BUMPING.md)** - Release process

## 🔄 Recent Updates

### v1.0.4 (2025-01-05)
- ✅ **Real-time GPS**: Reduced Watch GPS throttle from 10s to 0.5s (20x improvement)
- ✅ **Heading updates**: Immediate compass rotation response on iPhone
- ✅ **WebSocket toggle**: Enable/disable external relay (disabled by default)
- ✅ **Enhanced telemetry**: Queue depth, drops, duplicates, connectivity events

### v1.0.3 (2025-01-04)
- ✅ Comprehensive telemetry system
- ✅ Stream health monitoring
- ✅ Test suite expansion (81 tests)

See [STATUS.md](STATUS.md) for full changelog.

## 🛠️ Development

### Build Configuration

Version management via `Config/Shared.xcconfig`:
```
MARKETING_VERSION = 1.0.4
CURRENT_PROJECT_VERSION = 5
```

### Tracking Modes

| Mode | GPS Throttle | Update Rate | Battery Use | Use Case |
|------|--------------|-------------|-------------|----------|
| **Real-Time** | 0.5s | ~2Hz | ~30%/hr | Live tracking, pet safety |
| **Balanced** | 5s | 0.2Hz | ~15%/hr | General tracking |
| **Power Saver** | 30s | 0.03Hz | ~8%/hr | All-day tracking |
| **Minimal** | 120s | 0.008Hz | ~4%/hr | Battery conservation |

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style

- Swift 6.0+ with strict concurrency checking
- SwiftUI for all UI components
- Comprehensive unit tests for new features
- Document public APIs with DocC comments

## 📋 Requirements

### Minimum Versions
- iOS 18.0+
- watchOS 11.0+
- Xcode 16.0+
- Swift 6.0+

### Device Requirements
- iPhone 11+ (for base station/display)
- Apple Watch Series 4+ (for GPS tracking)
- Cellular Apple Watch recommended for LTE tracking

### Frameworks
- SwiftUI (UI)
- CoreLocation (GPS)
- WatchConnectivity (Watch ↔ iPhone communication)
- HealthKit (Watch workout sessions)
- Combine (Reactive streams)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with Swift 6.0 and SwiftUI
- Uses Apple's WatchConnectivity framework for reliable Watch-iPhone communication
- Inspired by real-world GPS tracking needs for pets, family safety, and outdoor activities

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/stonezone/gps-relay-framework/issues)
- **Documentation**: [docs/](docs/)
- **Discussions**: [GitHub Discussions](https://github.com/stonezone/gps-relay-framework/discussions)

---

**Made with ❤️ for real-time GPS tracking on Apple platforms**
