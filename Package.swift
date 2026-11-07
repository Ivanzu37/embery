// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Embery",
    platforms: [.macOS("27.0")],
    targets: [
        .executableTarget(name: "Embery", path: "Sources/Embery", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "EmberyTests", dependencies: ["Embery"], path: "Tests/EmberyTests", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
