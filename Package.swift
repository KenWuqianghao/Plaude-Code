// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PlaudeCode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PlaudeCode", targets: ["PlaudeCode"])
    ],
    targets: [
        .executableTarget(
            name: "PlaudeCode",
            path: "Sources"
        )
    ]
)
