// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SentinelAPI",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SentinelAPI",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AWSSQS", package: "aws-sdk-swift"),
            ],
            path: "Sources/SentinelAPI",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "SentinelAPITests",
            dependencies: [
                .target(name: "SentinelAPI"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/SentinelAPITests"
        ),
    ]
)
