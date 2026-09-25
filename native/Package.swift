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
        .library(name: "CrucibleText", targets: ["CrucibleText"]),
        .executable(name: "crucible-bench", targets: ["CrucibleBench"]),
    ],
    targets: [
        .target(
            name: "CrucibleCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Drawing letters, and nothing else.
        //
        // Words made of particles need a picture of the word first, and drawing type needs fonts — which
        // CrucibleCore is not allowed to reach for, and rightly. But putting it in the app instead would put
        // it somewhere nothing can test, and "is the picture the right way up" is not a question reading the
        // code answers. So it sits here: CoreText only, no UIKit, which means it builds and runs under
        // `swift test` on the macOS half of the checks. On Linux it compiles away to nothing.
        .target(
            name: "CrucibleText",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        // Measures the simulation rather than guessing at it. Performance claims
        // about this port should come from `swift run -c release crucible-bench`
        // on real hardware, not from reasoning about what ought to be fast.
        .executableTarget(
            name: "CrucibleBench",
            dependencies: ["CrucibleCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "CrucibleCoreTests",
            dependencies: ["CrucibleCore"],
            // Fixtures/ holds data extracted verbatim from the web reference
            // implementation, used to verify the port against its source rather
            // than against hand-written expectations. See
            // Fixtures/README.md for how to regenerate it.
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "CrucibleTextTests",
            dependencies: ["CrucibleText", "CrucibleCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
