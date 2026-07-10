// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BadgerKit",
    // iOS floor raised to 18 for IndexedEntity (App Intents Spotlight, M4). The app's
    // real floor is 26.1 (D9); newer APIs (AlarmKit 26.1) stay behind explicit
    // @available, per this package's convention. macOS stays v14 (the iOS-only App
    // Intents surface is #if os(iOS)-guarded, so `swift test` on the host is unaffected).
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "BadgerKit", targets: ["BadgerKit"]),
    ],
    targets: [
        .target(name: "BadgerKit"),
        .testTarget(name: "BadgerKitTests", dependencies: ["BadgerKit"]),
    ]
)
