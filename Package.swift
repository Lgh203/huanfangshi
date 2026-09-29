// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HuanFangCore", platforms: [.macOS(.v13), .iOS(.v16)], products: [.library(name: "HuanFangCore", targets: ["HuanFangCore"])], targets: [.target(name: "HuanFangCore", path: "Core", resources: [.process("Resources")]), .testTarget(name: "HuanFangCoreTests", dependencies: ["HuanFangCore"], path: "Tests")])
