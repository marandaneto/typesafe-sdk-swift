// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SupportInboxFeature",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "SupportInboxFeature", targets: ["SupportInboxFeature"])],
    dependencies: [.package(path: "../../..")],
    targets: [
        .target(
            name: "SupportInboxFeature",
            dependencies: [.product(name: "TypeSafe", package: "typesafe-sdk-swift")]
        ),
        .testTarget(name: "SupportInboxFeatureTests", dependencies: ["SupportInboxFeature"]),
    ],
    swiftLanguageModes: [.v6]
)
