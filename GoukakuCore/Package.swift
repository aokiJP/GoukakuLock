// swift-tools-version: 6.0
import PackageDescription

// 合格ロックの「判定の芯」。Foundation だけに依存する純粋なロジック。
// 本体アプリ・DeviceActivityMonitor 拡張・Shield 拡張・ウィジェットのすべてがこれを共有する。
let package = Package(
    name: "GoukakuCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GoukakuCore", targets: ["GoukakuCore"]),
    ],
    targets: [
        .target(name: "GoukakuCore"),
        .testTarget(name: "GoukakuCoreTests", dependencies: ["GoukakuCore"]),
    ]
)
