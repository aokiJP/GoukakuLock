import AppIntents

/// アプリの中で開ける画面(コントロールセンター・アクションボタン・ショートカットから選ぶ)
enum GoukakuScreen: String, AppEnum {
    case checkIn
    case focusTimer
    case emergency

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "合格ロックの画面" }

    static var caseDisplayRepresentations: [GoukakuScreen: DisplayRepresentation] {
        [
            .checkIn: "チェックイン",
            .focusTimer: "集中タイマー",
            .emergency: "緊急解除",
        ]
    }
}

/// 合格ロックを開いて、指定の画面を出す。
/// コントロールからアプリを開くには、OpenIntent を本体とウィジェット拡張の両方に入れる必要がある(Apple の説明どおり)。
/// 実際に画面を切り替えるのは本体で perform されたとき。ScreenRouting は本体と拡張でそれぞれ用意する。
struct OpenGoukakuScreenIntent: OpenIntent {
    static var title: LocalizedStringResource { "合格ロックの画面を開く" }
    static var description: IntentDescription {
        IntentDescription("チェックイン・集中タイマー・緊急解除の画面を開きます。")
    }

    @Parameter(title: "画面", default: .checkIn)
    var target: GoukakuScreen

    init() {}

    init(target: GoukakuScreen) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ScreenRouting.open(target)
        return .result()
    }
}
