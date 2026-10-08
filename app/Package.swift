// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeGuardian",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeGuardian",
            path: "Sources/ClaudeGuardian"
        )
    ]
)
