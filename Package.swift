// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "siriready",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "siriready", targets: ["siriready"]),
    ],
    targets: [
        // Audit, dataset, mock resolver, scoring and reporting. Foundation only.
        .target(name: "SiriReadyCore"),
        .executableTarget(name: "siriready", dependencies: ["SiriReadyCore"]),
        .testTarget(name: "SiriReadyTests", dependencies: ["SiriReadyCore"]),
    ]
)
