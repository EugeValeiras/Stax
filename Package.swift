// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stax",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Stax", path: "Sources/Stax"),
    ]
)
