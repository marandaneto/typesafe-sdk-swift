// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "typesafe-sdk-swift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
        .macCatalyst(.v16),
    ],
    products: [
        .library(name: "TypeSafe", targets: ["TypeSafe"]),
    ],
    targets: [
        .target(name: "TypeSafe"),
        .testTarget(
            name: "TypeSafeTests",
            dependencies: ["TypeSafe"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "TypeSafeIntegrationTests",
            dependencies: ["TypeSafe"],
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
