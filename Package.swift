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
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "vLens",
            dependencies: ["vLensCore"],
            path: "Sources/vLens",
            resources: [.copy("Resources/AppIconImage.png")],
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"])
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
