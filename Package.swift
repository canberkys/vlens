// swift-tools-version: 6.0
// vLens v0.1.0 - native macOS RVTools alternative
import PackageDescription

let package = Package(
    name: "vLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "vLens", targets: ["vLens"]),
        .executable(name: "vlens-cli", targets: ["vlens-cli"]),
        .library(name: "vLensCore", targets: ["vLensCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "vLens",
            dependencies: ["vLensCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/vLens",
            resources: [.copy("Resources/AppIconImage.png"), .copy("Resources/CHANGELOG.md")],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ],
            // Sparkle.framework is embedded at Contents/Frameworks in the
            // packaged .app (see scripts/release.sh) — the conventional
            // macOS location, found via the conventional rpath. SwiftPM's
            // default rpath (@loader_path) would instead look next to the
            // binary itself in Contents/MacOS, which isn't where a
            // framework belongs.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .executableTarget(
            name: "vlens-cli",
            dependencies: ["vLensCore"],
            path: "Sources/vLensCLI",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .target(
            name: "vLensCore",
            dependencies: ["ZIPFoundation"],
            path: "Sources/vLensCore",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
            ]
        ),
        .testTarget(
            name: "vLensCoreTests",
            dependencies: ["vLensCore", "ZIPFoundation"],
            path: "Tests/vLensCoreTests"
        )
    ]
)
