// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RawForge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "RawForgeCore", targets: ["RawForgeCore"]),
        .executable(name: "RawForgeApp", targets: ["RawForgeApp"]),
        .executable(name: "RawForgeVerify", targets: ["RawForgeVerify"])
    ],
    targets: [
        .target(
            name: "RawForgeCore",
            path: "Sources/RawForgeCore"
        ),
        .executableTarget(
            name: "RawForgeApp",
            dependencies: ["RawForgeCore"],
            path: "Sources/RawForgeApp"
        ),
        .executableTarget(
            name: "RawForgeVerify",
            dependencies: ["RawForgeCore"],
            path: "Sources/RawForgeVerify"
        )
    ]
)
