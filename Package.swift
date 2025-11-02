// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iosTracker",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "LocationCore", targets: ["LocationCore"]),
        .library(name: "WatchLocationProvider", targets: ["WatchLocationProvider"]),
        .library(name: "LocationRelayService", targets: ["LocationRelayService"]),
        .library(name: "LocationTransports", targets: ["WebSocketTransport", "BlePeripheralTransport"]),
        .library(name: "WebSocketTransport", targets: ["WebSocketTransport"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LocationCore",
            dependencies: [],
            path: "Sources/LocationCore"
        ),
        .target(
            name: "WatchLocationProvider",
            dependencies: ["LocationCore"],
            path: "Sources/WatchLocationProvider"
        ),
        .target(
            name: "LocationRelayService",
            dependencies: ["LocationCore"],
            path: "Sources/LocationRelayService"
        ),
        .target(
            name: "WebSocketTransport",
            dependencies: ["LocationCore"],
            path: "Sources/WebSocketTransport"
        ),
        .target(
            name: "BlePeripheralTransport",
            dependencies: ["LocationCore"],
            path: "Sources/BlePeripheralTransport"
        ),
        .testTarget(
            name: "LocationCoreTests",
            dependencies: ["LocationCore"],
            path: "Tests/LocationCoreTests"
        ),
        .testTarget(
            name: "WatchLocationProviderTests",
            dependencies: ["WatchLocationProvider", "LocationCore"],
            path: "Tests/WatchLocationProviderTests",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "LocationRelayServiceTests",
            dependencies: ["LocationRelayService", "LocationCore"],
            path: "Tests/LocationRelayServiceTests"
        )]
)
