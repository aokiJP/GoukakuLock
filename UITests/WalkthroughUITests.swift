import XCTest

/// シミュレータで画面を一通り動かし、各画面のスクリーンショットを残す(DEBUG ビルドで実行)。
/// Screen Time の許可はシミュレータでは得られないので、はじめの設定の「デバッグ」の抜け道を使う。
final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["TZ"] = "Asia/Tokyo"
        app.launch()

        // S-01 はじめの設定
        waitFor(app.buttons["わかった"])
        snap("01-はじめに")
        tap(app.buttons["わかった"])

        waitFor(app.buttons["許可なしで進む(デバッグ)"])
        snap("02-ScreenTimeの許可")
        tap(app.buttons["許可なしで進む(デバッグ)"])

        waitFor(app.buttons["通知を許可する"])
        snap("03-通知")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["対象を選ばずに進む(デバッグ)"])
        snap("04-ロック対象")
        tap(app.buttons["対象を選ばずに進む(デバッグ)"])

        waitFor(app.buttons["次へ"])
        snap("05-時刻とモード")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["次へ"])
        snap("06-最初のコミット")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["start.now"])
        snap("07-開始")
        tap(app.buttons["start.now"])
        waitFor(app.alerts.buttons["今すぐ始める"])
        snap("08-今すぐの確認")
        tap(app.alerts.buttons["今すぐ始める"])

        waitFor(app.buttons["はじめる"])
        snap("09-置き場所")
        tap(app.buttons["はじめる"])

        // S-02 ホーム(未達成)
        let checkIn = app.buttons["チェックイン"].firstMatch
        waitFor(checkIn, timeout: 15)
        snap("10-ホーム-未達成")

        // S-03 チェックイン
        tap(checkIn)
        let note = app.textViews.firstMatch.waitForExistence(timeout: 5) ? app.textViews.firstMatch : app.textFields.firstMatch
        waitFor(note)
        note.tap()
        note.typeText("Did 20 words. Self test 8/10")
        snap("11-チェックイン")
        tap(app.buttons["記録する"])
        waitFor(app.staticTexts["記録しました"])
        snap("12-記録しました")
        tap(app.buttons["閉じる"].firstMatch)

        // S-02 ホーム(達成)
        waitFor(app.buttons["緊急解除"])
        snap("13-ホーム-達成")

        // S-05 履歴
        tap(app.tabBars.buttons["記録"])
        sleep(1)
        snap("14-記録")

        // S-06 設定
        tap(app.tabBars.buttons["設定"])
        sleep(1)
        snap("15-設定")

        // S-04 コミットの編集
        tap(app.buttons["コミットの一覧と編集"])
        sleep(1)
        snap("16-コミット一覧")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // S-07 緊急解除・S-08 一時停止
        tap(app.tabBars.buttons["今日"])
        tap(app.buttons["緊急解除"])
        waitFor(app.buttons["緊急解除を申請する"])
        snap("17-緊急解除")
        tap(app.buttons["閉じる"].firstMatch)
        tap(app.buttons["一時停止"])
        sleep(1)
        snap("18-一時停止")
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "見つからない: \(element)", file: file, line: line)
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, file: file, line: line)
        element.tap()
    }

    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)   // 遷移のアニメーションを待つ
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
