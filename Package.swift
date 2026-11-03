// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VideoSizeLimiter",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VideoSizeLimiter", targets: ["VideoSizeLimiter"])],
    targets: [
        .target(name: "VideoSizeCore"),
        .executableTarget(name: "VideoSizeLimiter", dependencies: ["VideoSizeCore"]),
        .testTarget(name: "VideoSizeCoreTests", dependencies: ["VideoSizeCore"])
    ],
    swiftLanguageModes: [.v5]
)
