// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do checkout do neyhub ao lado (ou NEYHUB_PATH). A identidade de `.package(path:)` é o nome
// da pasta em minúsculas, então derivamos dela: funciona com worktrees.
let neyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub"
let hub = URL(fileURLWithPath: neyhub).lastPathComponent.lowercased()
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Hub",
    // O Hub exige macOS 15; o NeyHub (macOS 14) confere o `minMacOS` do plugin.json antes de carregar.
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Hub", targets: ["Hub"]),
        .library(name: "HubPlugin", type: .dynamic, targets: ["HubPlugin"]),
    ],
    dependencies: [.package(path: neyhub)],
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
