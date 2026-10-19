// swift-tools-version:5.10
import PackageDescription

// NameShiftCore holds all logic that can be tested without UI or permissions
// (trigger state machine, gate, wheel geometry, actions, converters, output policy).
// NameShift is the thin AppKit/SwiftUI shell: event tap, panels, menu bar, onboarding.
let package = Package(
    name: "NameShift",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NameShift", targets: ["NameShift"]),
    ],
    targets: [
        .target(name: "NameShiftCore", path: "Sources/NameShiftCore"),
        .executableTarget(
            name: "NameShift",
            dependencies: ["NameShiftCore"],
            path: "Sources/NameShift"
        ),
        .testTarget(
            name: "NameShiftCoreTests",
            dependencies: ["NameShiftCore"],
            path: "Tests/NameShiftCoreTests"
        ),
    ]
)
