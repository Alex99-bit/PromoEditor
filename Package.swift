// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromoEditor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PromoEditor", targets: ["PromoEditor"])
    ],
    targets: [
        .executableTarget(
            name: "PromoEditor",
            path: "Sources/PromoEditor"
        )
    ],
    swiftLanguageModes: [.v5]
)
