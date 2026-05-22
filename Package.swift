// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Schloop",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Schloop", targets: ["Schloop"]),
    ],
    targets: [
        .executableTarget(
            name: "Schloop",
            path: "Sources/Schloop"
        ),
    ]
)
