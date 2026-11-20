// swift-tools-version: 6.3

import PackageDescription

let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "MultiScreenRecorder",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2"),
    ],
    targets: [
        .target(
            name: "RecorderLogic",
            swiftSettings: strictSettings
        ),
        .target(
            name: "RecorderCore",
            dependencies: ["RecorderLogic"],
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "msr",
            dependencies: [
                "RecorderLogic",
                "RecorderCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSettings
        ),
        // The end-to-end tests (docs/design/end-to-end-tests.md): test
        // equipment, never in the app bundle.
        .target(
            name: "VirtualScreen",
            cSettings: [.unsafeFlags(["-Werror"])]
        ),
        .target(
            name: "EndToEndLogic",
            swiftSettings: strictSettings
        ),
        .executableTarget(
            name: "msr-end-to-end",
            dependencies: [
                "EndToEndLogic",
                "VirtualScreen",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "RecorderLogicTests",
            dependencies: ["RecorderLogic"],
            exclude: ["Fixtures"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "RecorderCoreTests",
            dependencies: ["RecorderCore", "RecorderLogic"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["msr", "RecorderCore", "RecorderLogic"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "EndToEndLogicTests",
            dependencies: ["EndToEndLogic"],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "CommandTests",
            dependencies: ["msr", "msr-end-to-end"],
            swiftSettings: strictSettings
        ),
    ]
)
