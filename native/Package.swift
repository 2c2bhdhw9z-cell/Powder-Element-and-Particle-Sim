// swift-tools-version: 6.0
import PackageDescription

// CrucibleCore is the simulation engine, and nothing else.
//
// It deliberately imports no Apple-only frameworks (no Metal, no SwiftUI, no
// UIKit, no CoreMotion), which buys two things:
//
//   1. It compiles and unit-tests on Linux, so the physics can be verified
//      without Apple hardware. The web reference implementation's test suite is
//      translated here and acts as the behavioral oracle.
//   2. It keeps the engine honest. Anything that needs a screen, a sensor or a
//      GPU lives in the app target instead (see ../App and ../project.yml), so
//      the engine can never quietly grow a UI dependency.
//
// The iOS app links this package as a local dependency.
let package = Package(
    name: "CrucibleCore",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "CrucibleCore", targets: ["CrucibleCore"]),
    ],
    targets: [
        .target(
            name: "CrucibleCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "CrucibleCoreTests",
            dependencies: ["CrucibleCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
