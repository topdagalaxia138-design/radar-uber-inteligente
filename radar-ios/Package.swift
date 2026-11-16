// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "RadarCore",
    products: [.library(name: "RadarCore", targets: ["RadarCore"])],
    targets: [
        .target(name: "RadarCore", path: "Shared"),
        .testTarget(name: "RadarCoreTests", dependencies: ["RadarCore"], path: "Tests")
    ]
)
