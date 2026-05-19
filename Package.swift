// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Audova",
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
