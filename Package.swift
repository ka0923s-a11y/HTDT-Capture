// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HTDTCapture",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "HTDTCaptureCore", targets: ["HTDTCaptureCore"]),
        .library(name: "HTDTCapturePlatform", targets: ["HTDTCapturePlatform"]),
        .library(name: "HTDTCaptureAppShell", targets: ["HTDTCaptureAppShell"]),
    ],
    targets: [
        .target(name: "HTDTCaptureCore"),
        .target(
            name: "HTDTCapturePlatform",
            dependencies: ["HTDTCaptureCore"]
        ),
        .target(
            name: "HTDTCaptureAppShell",
            dependencies: ["HTDTCaptureCore", "HTDTCapturePlatform"]
        ),
        .testTarget(
            name: "HTDTCaptureCoreTests",
            dependencies: ["HTDTCaptureCore"]
        ),
        .testTarget(
            name: "HTDTCapturePlatformTests",
            dependencies: ["HTDTCapturePlatform"]
        ),
    ]
)
