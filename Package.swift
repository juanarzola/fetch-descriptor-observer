// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fetch-descriptor-observer",
    platforms: [
      .macOS("15.0"),
      .iOS("17.0"),
      .tvOS("18.0"),
      .watchOS("11.0")
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FetchDescriptorObserver",
            targets: ["FetchDescriptorObserver"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FetchDescriptorObserver",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]
        ),
        .testTarget(
            name: "FetchDescriptorObserverTests",
            dependencies: ["FetchDescriptorObserver"]
        ),
    ]
)
