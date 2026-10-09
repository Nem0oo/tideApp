// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tide",
    platforms: [.iOS("17.0")],
    products: [
        .library(name: "Tide", targets: ["Tide"]),
        .library(name: "TideWidgetExtension", targets: ["TideWidgetExtension"]),
    ],
    targets: [
        .target(name: "Tide", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "TideWidgetExtension", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
