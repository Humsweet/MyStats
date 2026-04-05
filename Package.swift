// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyStats",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MyStats", targets: ["MyStats"])
    ],
    targets: [
        .executableTarget(
            name: "MyStats",
            dependencies: []
        )
    ]
)
