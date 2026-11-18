// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BetterWacom",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "BetterWacom",
            path: "Sources/BetterWacom",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
