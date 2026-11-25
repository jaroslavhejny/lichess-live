// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ChessKit", platforms: [.macOS(.v14)], products: [.library(name: "ChessKit", targets: ["ChessKit"])], targets: [.target(name: "ChessKit")])
