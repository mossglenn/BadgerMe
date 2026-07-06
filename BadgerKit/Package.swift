// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BadgerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BadgerKit", targets: ["BadgerKit"]),
    ],
    targets: [
        .target(name: "BadgerKit"),
        .testTarget(name: "BadgerKitTests", dependencies: ["BadgerKit"]),
    ]
)
