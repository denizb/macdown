// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDown",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "MacDown", path: "Sources/MacDown"),
        .testTarget(name: "MacDownTests", dependencies: ["MacDown"], path: "Tests/MacDownTests"),
    ]
)
