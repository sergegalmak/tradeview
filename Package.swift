// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tradeview",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tradeview", targets: ["Tradeview"])
    ],
    targets: [
        .target(name: "TradeviewCore"),
        .executableTarget(name: "Tradeview", dependencies: ["TradeviewCore"]),
        .testTarget(name: "TradeviewCoreTests", dependencies: ["TradeviewCore"]),
        .testTarget(name: "TradeviewTests", dependencies: ["Tradeview", "TradeviewCore"])
    ]
)
