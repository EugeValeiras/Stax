// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Stax",
    platforms: [.macOS(.v14)],
    targets: [
        // Declaraciones de la API privada de pantallas virtuales de CoreGraphics (ver StaxPrivate.h).
        .target(name: "StaxPrivate", path: "Sources/StaxPrivate"),
        .executableTarget(name: "Stax", dependencies: ["StaxPrivate"], path: "Sources/Stax"),
    ]
)
