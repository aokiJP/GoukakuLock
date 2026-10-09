// swift-tools-version: 6.0
import PackageDescription

// 合格ロックの iOS 側の共有部品(仕様書 第17.1〜17.4節)。
// ManagedSettings・DeviceActivity・FamilyControls・UserNotifications を使うので iOS 専用。
// 本体アプリと拡張3つ(Monitor・ShieldConfiguration・ShieldAction)がこれを共有する。
let package = Package(
    name: "GoukakuKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "GoukakuKit", targets: ["GoukakuKit"]),
    ],
    dependencies: [
        .package(path: "../GoukakuCore"),
    ],
    targets: [
        .target(
            name: "GoukakuKit",
            dependencies: [.product(name: "GoukakuCore", package: "GoukakuCore")]
        ),
    ]
)
