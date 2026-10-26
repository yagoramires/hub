// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do neyhub publicado no GitHub. Para desenvolver junto com um checkout local: NEYHUB_PATH=../neyhub
// (a identidade de `.package(path:)` é o nome da pasta em minúsculas, então derivamos dela: funciona com worktrees).
let localNeyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"]
let hub = localNeyhub.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? "neyhub"
let neyhubPackage: Package.Dependency = localNeyhub.map { .package(path: $0) }
    ?? .package(url: "https://github.com/yagoramires/neyhub.git", from: "0.1.0")
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Hub",
    // O Hub exige macOS 15; o NeyHub (macOS 14) confere o `minMacOS` do plugin.json antes de carregar.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hub", targets: ["Hub"]),
        .library(name: "HubPlugin", type: .dynamic, targets: ["HubPlugin"]),
    ],
    dependencies: [neyhubPackage],
    targets: [
        .target(name: "HubCore", dependencies: [.product(name: "NeyKit", package: hub)], path: "Sources/HubCore", swiftSettings: swift5),
        .executableTarget(
            name: "Hub",
            dependencies: ["HubCore", .product(name: "NeyKitApp", package: hub)],
            path: "Sources/Hub",
            swiftSettings: swift5
        ),
        // Plugin do NeyHub: nunca linka NeyKitApp (classes duplicadas no processo do NeyHub).
        .target(name: "HubPlugin", dependencies: ["HubCore", .product(name: "NeyKit", package: hub)], path: "Sources/HubPlugin", swiftSettings: swift5),
    ]
)
