# Apple Watch Physical Device Deployment Guide

## Current Status
- ✅ Watch app builds successfully
- ✅ Watch app runs in simulator
- ✅ Developer Mode enabled on Apple Watch Ultra
- ⚠️ Watch tunnel connection unstable (common issue)

## Prerequisites
- Apple Watch paired with iPhone
- iPhone connected to Mac via USB cable
- Developer Mode enabled on Apple Watch (Settings → Privacy & Security → Developer Mode)
- Xcode installed with watchOS SDK

## Watch Connection Requirements

Apple Watch connects to Xcode through the paired iPhone using a network tunnel. For deployment to succeed:

1. **iPhone must be connected via USB cable** ✅ (You have this)
2. **Watch must be awake and unlocked**
   - Tap the watch screen or press Digital Crown
   - Keep screen on during deployment
3. **Watch must be within Bluetooth range of iPhone**
   - Keep watch on wrist or very close to iPhone
4. **Network tunnel must be established**
   - Check status: `xcrun devicectl list devices`
   - Watch should show `connected` not `available (paired)`

## Troubleshooting Connection Issues

### Check Connection Status
```bash
xcrun devicectl list devices
```

Expected output for working connection:
```
Name                 State        Model
------------------   ----------   --------------
SpurgleboozerXII     connected    iPhone 15 Pro Max
zack's Apple Watch   connected    Apple Watch Ultra
```

### Check Tunnel State
```bash
xcrun devicectl device info details --device <WATCH_UDID> 2>&1 | grep "tunnelState"
```

Should show: `tunnelState: connected`

### Common Fixes

1. **Restart Xcode device services**
   ```bash
   killall -9 XCBDeviceService DVTDeviceHub
   ```

2. **Wake and unlock the watch**
   - Tap screen or press Digital Crown
   - Ensure screen stays on

3. **Restart Bluetooth**
   - On iPhone: Settings → Bluetooth → Toggle off/on
   - On Mac: System Settings → Bluetooth → Toggle off/on

4. **Restart watch networking**
   - Put watch in Airplane Mode for 5 seconds
   - Turn Airplane Mode off

5. **Restart iPhone connection**
   - Unplug iPhone from Mac
   - Wait 5 seconds
   - Plug back in and trust computer

6. **Last resort: Re-pair watch**
   - Unpair watch from iPhone (all data will be erased)
   - Pair watch again
   - Enable Developer Mode again

## Deployment Commands

Once watch shows as `connected` in device list:

### 1. Build for Physical Device
```bash
cd /Users/zackjordan/code/jetson/orin/iosTracker_class
xcodebuild -project iosTrackerApp.xcodeproj \
  -scheme "watchTrackerApp Watch App" \
  -destination "platform=watchOS,id=00008301-989895C41E80202E" \
  build
```

### 2. Install App
```bash
# Get app path first
APP_PATH=$(xcodebuild -project iosTrackerApp.xcodeproj \
  -scheme "watchTrackerApp Watch App" \
  -destination "platform=watchOS,id=00008301-989895C41E80202E" \
  -showBuildSettings | grep " BUILD_DIR" | sed 's/.*= //')

# Install to watch
xcrun devicectl device install app \
  --device 00008301-989895C41E80202E \
  "${APP_PATH}/Debug-watchos/watchTrackerApp Watch App.app"
```

### 3. Launch App
```bash
xcrun devicectl device process launch \
  --device 00008301-989895C41E80202E \
  com.iostracker.watch.watchkitapp
```

## Alternative: Deploy from Xcode

1. Open `iosTrackerApp.xcodeproj` in Xcode
2. Select "watchTrackerApp Watch App" scheme
3. Select your Apple Watch as destination
4. Press ⌘R (Run) or click Play button
5. Watch for build progress in Xcode
6. App will install and launch automatically

## Device Information

Your Apple Watch Ultra:
- **UDID**: `00008301-989895C41E80202E`
- **Identifier**: `B36A6B0D-F3BC-543A-80FE-0757480C58EF`
- **Model**: Watch6,18
- **OS Version**: watchOS 26.1
- **Developer Mode**: Enabled ✅

Your iPhone 15 Pro Max:
- **UDID**: `44AC4E62-45B1-58A0-8571-857F1EC2E014`
- **Model**: iPhone16,2
- **OS Version**: iOS 26.1

## LTE Apple Watch Behavior

### Dual-Stream Architecture
The system maintains **two independent GPS streams**:
- **Base Stream (iPhone)**: Stationary reference with GPS + compass heading
- **Remote Stream (Watch)**: Mobile tracker wherever the wearer roams

### Watch Connectivity Modes

#### 1. Bluetooth Range (Preferred)
- **Range**: ~10-30 meters from iPhone
- **Latency**: <1 second for location updates
- **Data Path**: WatchConnectivity interactive messages
- **Reliability**: High (instant delivery)

#### 2. LTE Cellular (Extended Range)
- **Range**: Unlimited (independent of iPhone proximity)
- **Latency**: 2-10 seconds for location updates
- **Data Path**: WatchConnectivity background transfers + application context
- **Reliability**: Medium (network-dependent)

**Important LTE Limitations:**
- Apple Watch LTE uses **application context** for background delivery
- Updates are **throttled by watchOS** (not controlled by app)
- Expect 5-15 second intervals between updates when out of Bluetooth range
- Interactive messaging unavailable when iPhone unreachable
- Background file transfers used as fallback with retry queue

### Expected Update Rates

| Scenario | Update Frequency | Latency | Reliability |
|----------|-----------------|---------|-------------|
| Bluetooth range | 1-2 Hz | <1s | ✅ High |
| LTE nearby | 0.2-1 Hz | 2-5s | ⚠️ Medium |
| LTE distant | 0.06-0.2 Hz | 5-15s | ⚠️ Medium |
| Watch disconnected | 0 Hz | N/A | ❌ None |

### Operator Guidance

**For Base Station Setup:**
1. Place iPhone in stable location (desk, mount, etc.)
2. Connect to Jetson via USB tethering or WiFi
3. Start relay with WebSocket enabled
4. Verify base stream shows minimal movement (hysteresis mode active)

**For Remote Tracker Operation:**
1. Wear Apple Watch normally
2. Start workout-based tracking
3. Watch operates in Bluetooth range: expect real-time updates
4. Watch roams beyond Bluetooth: expect 5-15s update intervals (LTE)
5. Monitor "Remote Tracker" section in iPhone app for last update age

**Troubleshooting Remote Stream:**
- **No remote updates**: Check watch app is running and workout active
- **Stale remote data (>30s)**: Watch may be in power-saving mode or poor LTE signal
- **Duplicate sequence warnings**: Normal during connectivity transitions
- **Queue depth growing**: Watch experiencing connectivity issues, queue will flush when reachable

## Testing the App

Once deployed, the watch app should:
1. Show GPS Tracker interface with Start/Stop button
2. Display "Workout Status" section
3. Show "Fixes sent" counter
4. Display GPS coordinates when tracking (Lat, Lon, Accuracy, Altitude)
5. Send location fixes to paired iPhone via WatchConnectivity (multiple channels)

## Next Steps After Deployment

1. Test GPS tracking on watch
2. Verify location data appears in Xcode console
3. Test iPhone app receiving data from watch
4. Test end-to-end: Watch → iPhone → Jetson WebSocket server

## Known Issues

- **Tunnel disconnection**: The network tunnel between Mac and Watch can be unstable. This is a known Apple limitation.
- **Connection timing**: Watch may take 30-60 seconds to establish connection after waking.
- **First deployment**: First time deploying to a watch can take longer while symbols are cached.
- **WiFi vs Bluetooth**: Watch uses Bluetooth to iPhone primarily, but also uses WiFi if available.

## References

- Apple Developer: [Testing on Real Devices](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device)
- watchOS Development: [HealthKit Workouts](https://developer.apple.com/documentation/healthkit/workouts_and_activity_rings)
- Device Management: [devicectl](https://developer.apple.com/documentation/xcode/managing-devices-with-devicectl)
