// swift-tools-version: 6.0
import PackageDescription

// 合格ロックの「相棒AI」の芯。Foundation だけに依存する(Linux でも単体テストできる)。
// - モデルの目録・端末の様子から使うAIを決める仕組み(完全環境適応)
// - プロンプト・出力の読み取り・内容の安全確認
// - AIが使えないときの体験帳(ルールで選ぶ)
// - 体験の育ち(地図・AIの理解)と、safetensors の軽量化
// 実際にモデルを動かす部分(MLX)は GoukakuAIMLX、Apple Intelligence は本体アプリにある。
let package = Package(
    name: "GoukakuAI",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GoukakuAI", targets: ["GoukakuAI"]),
    ],
    targets: [
        .target(name: "GoukakuAI"),
        .testTarget(name: "GoukakuAITests", dependencies: ["GoukakuAI"]),
    ]
)
