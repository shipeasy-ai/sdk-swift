// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shipeasy",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "Shipeasy", targets: ["Shipeasy"]),
    ],
    targets: [
        .target(name: "Shipeasy"),
        .testTarget(name: "ShipeasyTests", dependencies: ["Shipeasy"]),
    ]
)
