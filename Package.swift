// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GuitarTuner",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GuitarTunerKit", targets: ["GuitarTunerKit"]),
        .library(name: "GuitarTunerUI", targets: ["GuitarTunerUI"]),
        .executable(name: "GuitarTunerMac", targets: ["GuitarTunerMac"]),
        .executable(name: "GuitarTunerChecks", targets: ["GuitarTunerChecks"]),
    ],
    targets: [
        // DSP + audio capture. No UI, fully testable on the command line.
        .target(name: "GuitarTunerKit"),

        // Shared SwiftUI layer (iOS + macOS).
        .target(name: "GuitarTunerUI", dependencies: ["GuitarTunerKit"]),

        // Runnable macOS app for local development (`swift run GuitarTunerMac`).
        .executableTarget(name: "GuitarTunerMac", dependencies: ["GuitarTunerUI", "GuitarTunerKit"]),

        // Verification suite for the DSP core: `swift run GuitarTunerChecks`.
        // Plain Swift on purpose — XCTest / swift-testing only ship with a full Xcode
        // installation, and the DSP has to be verifiable with the command line tools too.
        .executableTarget(name: "GuitarTunerChecks", dependencies: ["GuitarTunerKit"]),
    ]
)
