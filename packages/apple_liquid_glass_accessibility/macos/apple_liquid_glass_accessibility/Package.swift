// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "apple_liquid_glass_accessibility",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "apple-liquid-glass-accessibility", targets: ["apple_liquid_glass_accessibility"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "apple_liquid_glass_accessibility",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
