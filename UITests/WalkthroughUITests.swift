import XCTest

/// シミュレータで画面を一通り動かし、各画面のスクリーンショットを残す(DEBUG ビルドで実行)。
/// Screen Time の許可はシミュレータでは得られないので、はじめの設定の「デバッグ」の抜け道を使う。
final class WalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkthrough() throws {
        app = XCUIApplication()
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
        tap(app.alerts.buttons["今すぐ始める"])

        waitFor(app.buttons["はじめる"])
        snap("08-置き場所")
        tap(app.buttons["はじめる"])

        // S-02 ホーム(未達成)
        let checkIn = app.buttons["チェックイン"].firstMatch
        waitFor(checkIn, timeout: 15)
        snap("10-ホーム-未達成")

        // S-03 チェックイン → はじめての合格(はなまる)
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
        waitFor(app.staticTexts["はじめての合格"], timeout: 8)
        Thread.sleep(forTimeInterval: 1.6)   // はなまるを描き終えるまで
        snap("13-はじめての合格")
        tap(app.buttons["閉じる"].firstMatch)

        // S-02 ホーム(達成)
        waitFor(app.buttons["緊急解除"])
        snap("14-ホーム-達成")
        app.swipeUp()
        snap("15-ホーム-下")

        // 合格証
        scrollTo(app.buttons["合格証をつくる"])
        tap(app.buttons["合格証をつくる"])
        waitFor(app.navigationBars["合格証"])
        snap("16-合格証")
        tap(app.buttons["閉じる"].firstMatch)

        // S-04 コミットの追加(例から選ぶ・確かめ方)
        app.swipeDown()
        tap(app.buttons["コミット"])
        tap(app.buttons["追加"])
        tap(app.buttons["集中勉強"])
        snap("17-コミットを追加")
        app.swipeUp()
        snap("18-確かめ方")
        tap(app.buttons["保存"])
        tap(app.alerts.buttons["OK"])
        snap("19-コミット一覧")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // S-05 記録
        tap(app.tabBars.buttons["記録"])
        sleep(1)
        snap("20-記録")

        // S-06 設定と、使いこなす・アイコン・稼働型
        tap(app.tabBars.buttons["設定"])
        sleep(1)
        snap("21-設定")
        scrollTo(app.buttons["ウィジェット・Siri・通知から記録する"])
        tap(app.buttons["ウィジェット・Siri・通知から記録する"])
        sleep(1)
        snap("22-使いこなす")
        app.swipeUp()
        snap("23-使いこなす-下")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo(app.buttons["アイコン"])
        tap(app.buttons["アイコン"])
        sleep(1)
        snap("24-アイコン")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let lockMode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ロックモード'")).firstMatch
        scrollBackTo(lockMode)
        tap(lockMode)
        tap(app.buttons["稼働型(勉強で時間を稼ぐ)"])
        sleep(1)
        snap("25-稼働型")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // デバッグの見本(ウィジェット・Live Activity・お祝い・記録の画面)
        scrollTo(app.buttons["デバッグメニュー"])
        tap(app.buttons["デバッグメニュー"])
        scrollTo(app.buttons["ウィジェット・Live Activity・お祝い"])
        tap(app.buttons["ウィジェット・Live Activity・お祝い"])
        sleep(1)
        snap("26-見本-ウィジェット")
        bringToTop(app.staticTexts["ウィジェット(見本:ロック中)"])
        snap("27-見本-ウィジェット2")
        bringToTop(app.staticTexts["Live Activity"])
        snap("28-見本-LiveActivity")
        scrollTo(app.buttons["集中タイマー(見本)"])
        tap(app.buttons["集中タイマー(見本)"])
        tap(app.buttons["はじめる"])
        sleep(3)
        snap("29-集中タイマー")
        tap(app.buttons["やめる"])
        tap(app.buttons["写真で記録(見本)"])
        sleep(1)
        snap("30-写真で記録")
        tap(app.buttons["閉じる"].firstMatch)
        scrollTo(app.buttons["はなまるを出す(7日連続)"])
        tap(app.buttons["はなまるを出す(7日連続)"])
        waitFor(app.staticTexts["7日連続"])
        Thread.sleep(forTimeInterval: 1.8)
        snap("31-はなまる-7日")
        tap(app.buttons["閉じる"].firstMatch)
        tap(app.buttons["週のふり返りを開く"])
        sleep(1)
        snap("32-週のふり返り")
        tap(app.buttons["あとで"])
        scrollTo(app.staticTexts["合 格 証"])
        snap("33-合格証-見本")

        // S-07 緊急解除・S-08 一時停止
        tap(app.tabBars.buttons["今日"])
        scrollTo(app.buttons["緊急解除"])
        tap(app.buttons["緊急解除"])
        waitFor(app.buttons["緊急解除を申請する"])
        snap("34-緊急解除")
        tap(app.buttons["閉じる"].firstMatch)
        tap(app.buttons["一時停止"])
        sleep(1)
        snap("35-一時停止")
        tap(app.buttons["閉じる"].firstMatch)

        // ホーム画面のクイックアクション(アイコンを長押し →「チェックイン」)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["合格ロック"]
        waitFor(icon)
        var pages = 0
        while !icon.isHittable && pages < 4 {
            springboard.swipeLeft()
            pages += 1
        }
        icon.press(forDuration: 1.4)
        let quickCheckIn = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'チェックイン'")).firstMatch
        waitFor(quickCheckIn)
        snap("36-クイックアクション")
        quickCheckIn.tap()
        waitFor(app.navigationBars["チェックイン"], timeout: 15)
        snap("37-クイックアクションから")
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "見つからない: \(element)", file: file, line: line)
    }

    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitFor(element, file: file, line: line)
        element.tap()
    }

    /// 見えるところまで上へスクロールする
    @MainActor
    private func scrollTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var tries = 0
        while (!element.exists || !element.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.exists, "スクロールしても見つからない: \(element)", file: file, line: line)
    }

    /// 要素を画面の上のほうまで持ってくる(スクリーンショットの構図をそろえる)
    @MainActor
    private func bringToTop(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        scrollTo(element, file: file, line: line)
        if element.frame.midY > app.frame.height * 0.7 {
            // タブバーの近くにあるときは、まず少しだけ上げる
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.16))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// 見えるところまで下へ(画面の上のほうへ)戻る
    @MainActor
    private func scrollBackTo(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        var tries = 0
        while (!element.exists || !element.isHittable) && tries < 8 {
            app.swipeDown()
            tries += 1
        }
        XCTAssertTrue(element.exists, "スクロールしても見つからない: \(element)", file: file, line: line)
    }

    @MainActor
    private func snap(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)   // 遷移のアニメーションを待つ
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
