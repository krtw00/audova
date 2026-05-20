// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Audova",
    defaultLocalization: "ja",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Audova", targets: ["Audova"]),
        .library(name: "AudovaCore", targets: ["AudovaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", from: "0.12.1"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "AudovaCore",
            dependencies: [
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "Audova",
            dependencies: [
                "AudovaCore",
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            exclude: [
                // iconset はアイコン生成の元ソース。 runtime 不要なので exclude。
                "Resources/Audova.iconset",
                // Info.plist は Xcode build 時に自動 pick up される。 SwiftPM resource 登録は不可のため exclude。
                "Info.plist",
            ],
            resources: [
                .copy("Resources/Audova.icns"),
                .process("Resources/ja.lproj"),
            ]
        ),
        .testTarget(
            name: "AudovaCoreTests",
            dependencies: [
                "AudovaCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
