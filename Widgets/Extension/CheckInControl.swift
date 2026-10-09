import SwiftUI
import WidgetKit
import AppIntents
import GoukakuShared

/// コントロールセンター・ロック画面・アクションボタンから、チェックイン画面を開く
struct CheckInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKinds.checkInControl) {
            ControlWidgetButton(action: OpenCheckInFromControlIntent()) {
                Label("チェックイン", systemImage: "checkmark.seal")
            }
        }
        .displayName("合格ロックでチェックイン")
        .description("今日のコミットを記録する画面を開きます。")
    }
}

struct OpenCheckInFromControlIntent: AppIntent {
    static var title: LocalizedStringResource { "チェックイン画面を開く" }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(DeepLink.checkIn))
    }
}
