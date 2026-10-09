import SwiftUI
import WidgetKit

/// ホーム画面・ロック画面・StandBy のウィジェット、Live Activity、コントロールセンターのボタン
@main
struct GoukakuWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        GoukakuLiveActivity()
        CheckInControl()
    }
}
