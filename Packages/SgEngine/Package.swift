// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SgEngine",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "SgEngine", targets: ["SgEngine"]),
    ],
    targets: [
        .target(
            name: "SgEngine",
            path: "Sources/SgEngine"
        ),
        .testTarget(
            name: "SgEngineTests",
            dependencies: ["SgEngine"],
            path: "Tests/SgEngineTests"
        ),
    ]
)
