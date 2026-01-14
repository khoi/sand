// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "sand",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "sand", targets: ["sand"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0")
    ],
    targets: [
        .executableTarget(
            name: "sand",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "SwiftJWT", package: "Swift-JWT")
            ]
        ),
        .testTarget(
            name: "sandTests",
            dependencies: [
                "sand",
                .product(name: "Testing", package: "swift-testing")
            ]
        )
    ]
)
