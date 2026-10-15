// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CompanionCore", platforms: [.iOS(.v18), .macOS(.v14)], products: [.library(name: "CompanionCore", targets: ["CompanionCore"])], targets: [.target(name: "CompanionCore", path: "Sources/Core", resources: [.process("Resources")]), .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"], path: "Tests", exclude: ["UIBaseline018"], resources: [.process("Fixtures")])])
