// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AsobiCore", products: [.library(name: "AsobiCore", targets: ["AsobiCore"])], targets: [.target(name: "AsobiCore", path: "Core"), .testTarget(name: "AsobiCoreTests", dependencies: ["AsobiCore"], path: "Tests")])
