// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Hub",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Hub",
            path: "Sources/Hub",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
