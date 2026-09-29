// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tappy",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swhitty/SwiftDraw.git", from: "0.29.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // Testable core logic, free of UI.
        .target(
            name: "TappyCore",
            dependencies: [
                .product(name: "SwiftDraw", package: "SwiftDraw"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                // .copy keeps subdirectory structure; the CLT toolchain
                // cannot compile .xcstrings, so we ship plain .lproj
                // folders instead. Packs hold all content (artwork,
                // sounds, names) as data.
                .copy("Resources/Packs"),
                .copy("Resources/Licenses"),
                .copy("Resources/en.lproj"),
                .copy("Resources/zh-Hans.lproj"),
                .copy("Resources/ja.lproj"),
                .copy("Resources/ko.lproj"),
                .copy("Resources/es.lproj"),
                .copy("Resources/fr.lproj"),
                .copy("Resources/de.lproj"),
            ]
        ),
        // The app itself.
        .executableTarget(name: "Tappy", dependencies: ["TappyCore"]),
        // Assertion-based checks runnable without Xcode/XCTest.
        .executableTarget(name: "TappyChecks", dependencies: ["TappyCore"]),
        // Micro-benchmarks for the hot paths.
        .executableTarget(name: "TappyBench", dependencies: ["TappyCore"]),
    ]
)
