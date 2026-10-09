// swift-tools-version: 6.0
import PackageDescription

// 合格ロックの iOS 側の共有部品。
// - GoukakuShared:App Group・ディープリンク・ウィジェット用の要約・Live Activity の型(ウィジェットも使う。Family Controls なし)
// - GoukakuKit:ManagedSettings・DeviceActivity・FamilyControls・通知のつなぎ(仕様書 第17.1〜17.4節。本体と拡張3つ)
let package = Package(
    name: "GoukakuKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "GoukakuKit", targets: ["GoukakuKit"]),
        .library(name: "GoukakuShared", targets: ["GoukakuShared"]),
    ],
    dependencies: [
        .package(path: "../GoukakuCore"),
    ],
    targets: [
        .target(
            name: "GoukakuShared",
            dependencies: [.product(name: "GoukakuCore", package: "GoukakuCore")]
        ),
        .target(
            name: "GoukakuKit",
            dependencies: ["GoukakuShared", .product(name: "GoukakuCore", package: "GoukakuCore")]
        ),
    ]
)
