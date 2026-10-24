# 検証結果

- Swift 6.0.3 / Linux: 15 XCTestテスト成功（失敗0）。
- Core/Experience.swift: swiftc -typecheck 成功。
- App/*.swift, Core/*.swift: swiftc -parse 成功。これはiOS SDKを使う型検査・リンクではありません。
- iOSビルド・実機AI推論・SwiftUI操作・署名IPA: 未実施（Xcode/iOS SDK/署名資格なし）。
- UIの動作やAI出力品質を検証済みと解釈しないでください。

テストは固定fixtureを使った実行エンジンの検証です。fixtureはアプリに同梱されず、AIの代替として表示されません。ランダムの分岐選択はテスト時に固定し、アプリでは乱数を渡します。

- 両モデルの全manifest項目のSHA-256・サイズ・safetensorsのオフセット境界: 成功。
- Xcode project.pbxproj: OpenStep形式パース成功、参照ルート存在確認（iOSビルドの代替ではありません）。
- build.sh: bash -n 成功。
