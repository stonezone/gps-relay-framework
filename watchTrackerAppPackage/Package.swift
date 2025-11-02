// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "watchTrackerAppFeature",
    platforms: [.watchOS(.v10)],
    products: [
        .library(
            name: "watchTrackerAppFeature",
            targets: ["watchTrackerAppFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        .target(
            name: "watchTrackerAppFeature",
            dependencies: [
                .product(name: "LocationCore", package: "iosTracker_class"),
                .product(name: "WatchLocationProvider", package: "iosTracker_class")
            ]
        ),
        .testTarget(
            name: "watchTrackerAppFeatureTests",
            dependencies: [
                "watchTrackerAppFeature"
            ]
        ),
    ]
)
