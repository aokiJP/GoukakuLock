// swift-tools-version: 6.0
import PackageDescription

// 合格ロックの相棒AIを、この iPhone の中で動かす部分(MLX)。
// Apple の MLX(mlx-swift-lm)で、同梱・ダウンロード・取り込んだモデルを読み、文章を作る。
// トークナイザとチャットテンプレートは swift-transformers を使う(マクロは使わない)。
// iPhone 17 Pro・Qwen3.5 2B の実測で、MLX は llama.cpp・Core ML(ANE)より速かった(README 参照)。
let package = Package(
    name: "GoukakuAIMLX",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GoukakuAIMLX", targets: ["GoukakuAIMLX"]),
    ],
    dependencies: [
        .package(path: "../GoukakuAI"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.32.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.4"),
    ],
    targets: [
        .target(
            name: "GoukakuAIMLX",
            dependencies: [
                .product(name: "GoukakuAI", package: "GoukakuAI"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        // 実際のモデルで読み込みと生成を確かめる(GOUKAKU_MODEL_DIR を渡したときだけ動く。CI の macOS で使う)
        .testTarget(name: "GoukakuAIMLXTests", dependencies: ["GoukakuAIMLX"]),
    ]
)
