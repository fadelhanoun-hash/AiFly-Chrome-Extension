// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AiFlyMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AiFlyMac", targets: ["AiFlyMac"])],
    targets: [
        .executableTarget(
            name: "AiFlyMac",
            path: "Sources/AiFlyMac"
        )
    ]
)
