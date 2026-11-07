// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Embery",
    platforms: [.macOS("27.0")],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "Embery", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources/Embery",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework va en Contents/Frameworks de la app.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "EmberyTests", dependencies: ["Embery"], path: "Tests/EmberyTests", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
