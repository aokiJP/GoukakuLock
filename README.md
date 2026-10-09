# 合格ロック(GoukakuLock)

自分で決めた試験(目標)を、毎日の習慣にするための iOS アプリ。決めた時刻に、お金を使うアプリ(決済・買い物)とアプリ内課金を止め、その日のコミットを達成したと記録すると外れます。お金は没収も送金もされず、使えなくなるだけです。

設計は「合格ロック 完全仕様書(iOS)v3.0」のとおりで、このリポジトリはその**フェーズ1(MVP)**を実装したものです。

![ホーム(未達成)・チェックイン・ホーム(達成)・記録](docs/screens-main.jpg)

![はじめの設定](docs/screens-setup.jpg)

![設定・緊急解除・一時停止](docs/screens-settings.jpg)

スクリーンショットは CI の UI テストで撮ったもの(iPhone 17 シミュレータ・iOS 26.5)。シミュレータでは Screen Time の許可が得られないため、警告の帯が出ています。

見た目は「答案用紙と赤ペン」:状態は丸い印(はんこ)1つで表し、達成は朱の ◯、最小版は △、未達成は ✕ で記録します。

## いまの状態

| 項目 | 状態 |
|---|---|
| 判定の芯 GoukakuCore | 単体テスト 65 件が通過(macOS + Xcode 26.6、Linux + Swift 6.3.3) |
| iOS アプリ(本体+拡張3つ) | Xcode 26.6 / iOS 26.5 SDK でビルド成功。最低 iOS 18.0、iPhone 専用 |
| 画面の通し確認 | CI で iPhone 17 シミュレータ(iOS 26.5)を使い、はじめの設定 → チェックイン → 記録 → 設定 → 緊急解除 → 一時停止まで動かしてスクリーンショットを残す |
| 実機スパイク(第20章) | **未実施**。Screen Time API はシミュレータでは動かないので、ロックそのものは実機で確かめる |
| SP-01(無料の Apple ID で使えるか) | **使えない**で確定。Apple の DTS が、Personal Team(無料)では Family Controls を使えないと回答している |

### 実装したもの(フェーズ1)

- S-01 はじめの設定(8手順:説明 → Screen Time の許可 → 通知 → ロック対象と常に許可 → 日付切替とロックモード → 最初のコミット → 開始の時期 → 置き場所)
- S-02 ホーム(状態の印と見出し・次に変わる時刻までの残り・今日のコミット・連続/通算/最長・緊急解除と一時停止・警告の帯・3日連続未達成のときの「立て直し」)
- S-03 チェックイン(自己申告:一言メモ5文字以上・最小版は週の上限まで・5分以内の取り消し)
- S-04 コミットの追加・編集・削除(必須3つまで・曜日・最小版・本当の目標のメモ)
- S-05 記録(月のカレンダーを ◯ △ ✕ 休 などの記号と色で・連続/最長/通算/月の達成率・日ごとの一言・緊急解除の履歴)
- S-06 設定(ロック対象・ロックモード・日付切替は一時停止中だけ・アプリ内課金の禁止・最小版と休養日の上限・休養日・リマインド・回避ログ・書き出し・全削除)
- S-07 緊急解除(15分後から2時間・待機中の取り消し・今週の回数)
- S-08 一時停止・見守りモード・卒業の提案・「やめる合図」の一文
- 設定を緩められない仕組み(第7.5節):`ChangePolicy` で分類し、緩める変更は達成後だけ受け付けて翌サイクルから反映(予約中の変更として見える・取り消せる)
- 起動・前面復帰・バックグラウンド更新の処理(第16.4節):受信箱の取り込み、結果の確定、予約した変更の反映、区間の登録の確認、Screen Time の許可の確認、時刻改ざんの検知、リマインドの作り直し、バッジ
- 再インストールの検知(キーチェーンの印)、共有ファイルの復旧
- デバッグメニュー(Debug 版だけ):日付切替を任意の時刻に、緊急解除を短く(待機1分・解除15分)、今すぐ判定、ロックだけ外す、state.json・受信箱・登録中の区間の表示、ログの書き出し

### まだないもの(フェーズ2・3)

写真・タイマー・使用時間・稼働型・ウィジェット・Live Activity・週次レビュー・ドメインの直接指定(以上フェーズ2)、執行役・帳簿・ヘルスケア・場所つきタイマー・ショートカット(以上フェーズ3)。判定の芯(GoukakuCore)はこれらにも対応済みなので、画面と拡張を足せば動く作りです。

## ダウンロード

`main` に push するたびに GitHub Actions がビルドします。

- **Actions の Artifacts**:各実行の `GoukakuLock-ipa-<番号>`
- **Releases**:`v` で始まるタグを push したとき

| ファイル | 中身 |
|---|---|
| `GoukakuLock-Release.ipa` | ふだん使う版 |
| `GoukakuLock-Debug.ipa` | デバッグメニューつき。実機テスト(仕様書 第19.3節の T-01〜T-12)用 |

どちらも**未署名**(証明書なしのアドホック署名で、必要なエンタイトルメントだけが入っている)です。このままでは iPhone に入りません。

## 実機に入れる(署名)

### 必要なもの

- 有料の Apple Developer Program(無料の Apple ID では Family Controls を使えません)
- iOS 18.0 以上の iPhone

自分の iPhone に開発用として入れるだけなら、Family Controls の配布用(Distribution)の申請は要りません。ほかの人に配るなら、4つの Bundle ID それぞれについて申請が要ります(仕様書 第3.3節)。

### 1. Apple Developer のサイトで準備する(Mac は不要)

[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/) で次を作ります。

1. **App Group**:`group.com.aokijp.goukakulock`
2. **App ID を4つ**。それぞれの Capabilities で **Family Controls** と **App Groups** をオンにし、App Groups には 1 の App Group を割り当てる

   | バンドル | Bundle ID |
   |---|---|
   | 本体 `GoukakuLock.app` | `com.aokijp.goukakulock` |
   | `PlugIns/GoukakuMonitor.appex` | `com.aokijp.goukakulock.monitor` |
   | `PlugIns/GoukakuShieldConfig.appex` | `com.aokijp.goukakulock.shieldconfig` |
   | `PlugIns/GoukakuShieldAction.appex` | `com.aokijp.goukakulock.shieldaction` |

3. **Apple Development の証明書**(秘密鍵と合わせて `.p12` に書き出す)
4. **デバイス**(iPhone の UDID)の登録
5. **Development のプロビジョニングプロファイルを4つ**(上の App ID ごとに1つ)

Bundle ID を自分のものに変える場合は、拡張の ID を「本体の ID + `.monitor` など」にしてください。App Group の ID は、アプリが署名に使われたプロファイルから実行時に読み取るので、4つのプロファイルが同じ App Group を含んでいれば、ID を変えても動きます。

### 2. 署名し直す

4つのバンドルに、それぞれ対応するプロファイルを当てて署名します。例として、Linux・Windows・macOS で動く [zsign](https://github.com/zhlynn/zsign) なら、拡張の分も `-m` を重ねて渡せます。

```sh
zsign -k dev.p12 -p 'p12のパスワード' \
  -m goukakulock.mobileprovision \
  -m monitor.mobileprovision \
  -m shieldconfig.mobileprovision \
  -m shieldaction.mobileprovision \
  -o GoukakuLock-signed.ipa GoukakuLock-Release.ipa
```

署名後、4つのバンドルすべてに `com.apple.developer.family-controls` と `com.apple.security.application-groups` が残っていることを確かめてください。どれか1つでも欠けると、その拡張は動きません。

### 3. インストールする

署名済みの IPA は、署名をし直さずに入れる方法で入れます(例:zsign の `-i`(内部で ideviceinstaller を使う)、ideviceinstaller、Apple Configurator など)。署名をし直す種類のツールで入れると、拡張ごとのプロファイルが外れることがあります。

### Mac がある場合

```sh
brew install xcodegen
xcodegen generate     # project.yml から GoukakuLock.xcodeproj を作り直す
open GoukakuLock.xcodeproj
```

各ターゲット(本体と拡張3つ)の Signing & Capabilities で自分の Team を選べば、自動署名が App ID とプロファイルを作ります。iPhone をつないで Run すれば入ります。

## 最初に確かめること(実機)

Debug 版を入れて、仕様書 第20章のスパイクのうち SP-02〜SP-08・SP-10・SP-14 を先に確かめてください。手順は第19.3節の T-01〜T-12 で、デバッグメニュー(設定 › デバッグメニュー)を使います。

- **T-01**:日付切替を「今から20分後」に合わせ、端末をロックして待つ → 切替後に対象アプリを開くとシールドが出る → 本体でチェックインすると開ける
- **T-03**:「緊急解除を短くする」をオンにして申請 → 待機中はシールド、解除中は開ける、終了後は本体を閉じたままでもシールドに戻る
- **T-05**:「ロックを外す(判定はそのまま)」→ 対象アプリを1分以上使う → トリップワイヤーでロックが戻る

## 開発

```
GoukakuCore/      判定の芯(Foundation だけ。swift test で単体テスト 65 件)
GoukakuKit/       ManagedSettings・DeviceActivity・FamilyControls・通知のつなぎ(本体と拡張3つで共有)
Extensions/       Monitor・ShieldConfig・ShieldAction の各拡張
App/              本体アプリ(SwiftUI + SwiftData)
UITests/          シミュレータで画面を一通り動かしてスクリーンショットを残すテスト
project.yml       XcodeGen の定義(GoukakuLock.xcodeproj はここから生成)
scripts/          IPA に包むスクリプトなど
.github/workflows/build.yml   CI(テスト → ビルド → IPA → 画面の通し確認)
```

CI の結果(IPA・ビルドログ・スクリーンショット)は `ci-output` ブランチにも置かれます。

### スターター(仕様書の付録B)からの変更

- `AppGroup.identifier`:Info.plist の `GoukakuAppGroupID` と、署名に埋め込まれたプロビジョニングプロファイルから決める(再署名で ID が変わっても本体と拡張が同じ場所を見るため)
- `TargetsStore`:読み書きする場所を引数で渡せるようにした。`Reconciler.run` は `targets` を省くと、`store` と同じ場所の targets.json を読む
- `AppActions`:`clock` を拡張から使えるようにし、`requestEmergency` にデバッグ用の窓を渡せるようにした
- ShieldAction 拡張:iOS 26 で増えたサブメニューの項目も「閉じる」で受ける
- ShieldConfiguration 拡張:ボタンとアイコンを本体と同じ朱色に
