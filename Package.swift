// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromoEditor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PromoEditorCore", targets: ["PromoEditorCore"]),
        .executable(name: "PromoEditor", targets: ["PromoEditor"]),
        .executable(name: "PromoEditorCLI", targets: ["PromoEditorCLI"])
    ],
    targets: [
        .target(
            name: "PromoEditorCore",
            path: "Sources/PromoEditorCore"
        ),
        .executableTarget(
            name: "PromoEditor",
            dependencies: ["PromoEditorCore"],
            path: "Sources/PromoEditor"
        ),
        .executableTarget(
            name: "PromoEditorCLI",
            dependencies: ["PromoEditorCore"],
            path: "Sources/PromoEditorCLI"
        )
    ],
    swiftLanguageModes: [.v5]
)
