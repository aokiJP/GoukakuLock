import XCTest

/// シミュレータで画面を一通り動かし、各画面のスクリーンショットを残す(DEBUG ビルドで実行)。
/// Screen Time の許可はシミュレータでは得られないので、はじめの設定の「デバッグ」の抜け道を使う。
/// シミュレータでは MLX が動かないので、相棒AIは「見本のAI」(Gemma 4 E2B の出力をもとにした決まった文)で動かす。
final class WalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWalkthrough() throws {
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingScriptedAI", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchEnvironment["TZ"] = "Asia/Tokyo"
        app.launch()

        // S-01 はじめの設定
        waitFor(app.buttons["わかった"])
        snap("01-はじめに")
        tap(app.buttons["わかった"])

        // 相棒AI(この iPhone で使うAIと、あなたのこと)
        waitFor(app.navigationBars["相棒AI"])
        snap("02-相棒AI")
        // 「あなたのこと」は任意なので、入れられなくても先へ進む。
        // いちばん下の欄で「次へ」の帯に隠れやすいので、下までスクロールしてから押す
        app.swipeUp()
        app.swipeUp()
        let about = textInput()
        if about.waitForExistence(timeout: 3), focus(about) {
            app.typeText("English study. I like walking.")
            snap("02-相棒AI-あなたのこと")
        }
        if app.navigationBars["相棒AI"].exists {
            tap(app.buttons["次へ"])
        }

        waitFor(app.buttons["許可なしで進む(デバッグ)"])
        snap("03-ScreenTimeの許可")
        tap(app.buttons["許可なしで進む(デバッグ)"])

        waitFor(app.buttons["通知を許可する"])
        snap("04-通知")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["対象を選ばずに進む(デバッグ)"])
        snap("05-ロック対象")
        tap(app.buttons["対象を選ばずに進む(デバッグ)"])

        waitFor(app.buttons["次へ"])
        snap("06-時刻とモード")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["次へ"])
        snap("07-最初のコミット")
        tap(app.buttons["次へ"])

        waitFor(app.buttons["start.now"])
        snap("08-開始")
        tap(app.buttons["start.now"])
        tap(app.alerts.buttons["今すぐ始める"])

        waitFor(app.buttons["はじめる"])
        snap("09-置き場所")
        tap(app.buttons["はじめる"])

        // S-02 ホーム(未達成)
        let checkIn = app.buttons["チェックイン"].firstMatch
        waitFor(checkIn, timeout: 15)
        snap("10-ホーム-未達成")

        // ホームの「相棒から」:コミットを体験にする工夫
        scrollTo(app.buttons["companion.reframe"])
        tap(app.buttons["companion.reframe"])
        waitFor(anyElement(containing: "覚えた単語で今日を1文に"), timeout: 20)
        Thread.sleep(forTimeInterval: 1.5)
        snap("11-ホーム-相棒から")
        app.swipeDown()

        // S-03 チェックイン → 相棒のひとこと → はじめての合格(はなまる)
        tap(checkIn)
        let note = textInput()
        waitFor(note)
        XCTAssertTrue(focus(note), "一言の欄に入れられない")
        app.typeText("Did 20 words. Self test 8/10")
        snap("12-チェックイン")
        tap(app.buttons["記録する"])
        waitFor(app.staticTexts["記録しました"])
        waitFor(anyElement(containing: "単語に向き合った時間"), timeout: 20)
        snap("13-記録しました-相棒")
        tap(app.buttons["閉じる"].firstMatch)
        waitFor(app.staticTexts["はじめての合格"], timeout: 8)
        Thread.sleep(forTimeInterval: 1.6)   // はなまるを描き終えるまで
        snap("14-はじめての合格")
        tap(app.buttons["閉じる"].firstMatch)

        // S-02 ホーム(達成)
        waitFor(app.buttons["緊急解除"])
        snap("15-ホーム-達成")

        // 体験タブ:体験を3つ見つける → やってみる → やってみた → 相棒の返事
        tap(app.tabBars.buttons["体験"])
        waitFor(app.buttons["companion.suggest"])
        snap("20-体験")
        tap(app.buttons["companion.suggest"])
        let doIt = app.buttons["やってみる"].firstMatch
        waitFor(doIt, timeout: 30)
        // 3つそろうまで待つ
        let third = app.buttons.matching(NSPredicate(format: "label == 'やってみる'")).element(boundBy: 2)
        _ = third.waitForExistence(timeout: 30)
        Thread.sleep(forTimeInterval: 1.0)
        snap("21-体験-見つけた")
        app.swipeUp()
        snap("22-体験-見つけた-下")
        // 画面の中に見えている「やってみる」を押す(上に隠れかけたものを押すと、ナビゲーションバーに当たる)
        tap(visible(app.buttons.matching(NSPredicate(format: "label == 'やってみる'"))))
        scrollTo(app.buttons["やってみた"].firstMatch)
        snap("23-体験-やってみる")
        tap(app.buttons["やってみた"].firstMatch)
        // 気持ちを先に選ぶ(キーボードが出たあとだと、下の欄が隠れる)
        // 気持ちの「おだやか」(いまの調子の「おだやかに」とまちがえない)
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'おだやか' AND NOT (label CONTAINS 'おだやかに')")).firstMatch)
        let logNote = textInput()
        waitFor(logNote)
        XCTAssertTrue(focus(logNote), "体験の一言の欄に入れられない")
        app.typeText("The sky turned orange to purple.")
        snap("24-やってみた")
        tap(app.buttons["記録する"])
        waitFor(app.staticTexts["体験の地図に、ひとつ増えました"], timeout: 10)
        waitFor(app.buttons["覚えてもらう"].firstMatch, timeout: 20)
        snap("25-相棒の返事")
        // シートの下の一覧にも同じボタンがあるので、押せるほうを押す
        tap(firstHittable(app.buttons.matching(NSPredicate(format: "label == '覚えてもらう'"))))
        tap(app.buttons["閉じる"].firstMatch)

        // 相棒と話す
        scrollTo(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '相棒と話す'")).firstMatch)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '相棒と話す'")).firstMatch)
        waitFor(app.buttons["この週末、何をしてみよう"])
        snap("26-相棒と話す")
        tap(app.buttons["この週末、何をしてみよう"])
        waitFor(anyElement(containing: "外の音を3つ"), timeout: 20)
        snap("27-相棒と話す-返事")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // いつかの体験
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'いつかの体験'")).firstMatch)
        tap(app.buttons["いつかの体験を考える"])
        waitFor(app.buttons["とっておく"].firstMatch, timeout: 30)
        _ = app.buttons.matching(NSPredicate(format: "label == 'とっておく'")).element(boundBy: 2).waitForExistence(timeout: 30)
        snap("28-いつかの体験")
        tap(app.buttons["とっておく"].firstMatch)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 育ち(体験の地図・相棒が知っているあなた)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH '育ち'")).firstMatch)
        waitFor(app.navigationBars["育ち"])
        snap("29-育ち")
        app.swipeUp()
        snap("30-育ち-下")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 設定 › AI
        app.swipeDown()
        tap(app.buttons["AI"].firstMatch)
        waitFor(app.navigationBars["AI"])
        snap("31-AIの設定")
        app.swipeUp()
        snap("32-AIの設定-モデル")
        app.swipeUp()
        snap("33-AIの設定-下")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 合格証
        tap(app.tabBars.buttons["今日"])
        scrollTo(app.buttons["合格証をつくる"])
        tap(app.buttons["合格証をつくる"])
        waitFor(app.navigationBars["合格証"])
        snap("34-合格証")
        tap(app.buttons["閉じる"].firstMatch)

        // S-04 コミットの追加(例から選ぶ・確かめ方)
        app.swipeDown()
        app.swipeDown()
        tap(app.buttons["コミット"])
        tap(app.buttons["追加"])
        tap(app.buttons["集中勉強"])
        snap("35-コミットを追加")
        app.swipeUp()
        snap("36-確かめ方")
        tap(app.buttons["保存"])
        tap(app.alerts.buttons["OK"])
        snap("37-コミット一覧")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // S-05 記録
        tap(app.tabBars.buttons["記録"])
        sleep(1)
        snap("40-記録")

        // S-06 設定と、使いこなす・アイコン・稼働型
        tap(app.tabBars.buttons["設定"])
        sleep(1)
        snap("41-設定")
        scrollTo(app.buttons["ウィジェット・Siri・通知から記録する"])
        tap(app.buttons["ウィジェット・Siri・通知から記録する"])
        sleep(1)
        snap("42-使いこなす")
        app.swipeUp()
        snap("43-使いこなす-下")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollTo(app.buttons["アイコン"])
        tap(app.buttons["アイコン"])
        sleep(1)
        snap("44-アイコン")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let lockMode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ロックモード'")).firstMatch
        scrollBackTo(lockMode)
        tap(lockMode)
        tap(app.buttons["稼働型(勉強で時間を稼ぐ)"])
        sleep(1)
        snap("45-稼働型")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // デバッグの見本(ウィジェット・Live Activity・お祝い・記録の画面)
        scrollTo(app.buttons["デバッグメニュー"])
        tap(app.buttons["デバッグメニュー"])
        scrollTo(app.buttons["ウィジェット・Live Activity・お祝い"])
        tap(app.buttons["ウィジェット・Live Activity・お祝い"])
        sleep(1)
        snap("46-見本-ウィジェット")
        bringToTop(app.staticTexts["ウィジェット(見本:ロック中)"])
        snap("47-見本-ウィジェット2")
        bringToTop(app.staticTexts["Live Activity"])
        snap("48-見本-LiveActivity")
        scrollTo(app.buttons["集中タイマー(見本)"])
        tap(app.buttons["集中タイマー(見本)"])
        tap(app.buttons["はじめる"])
        sleep(3)
        snap("49-集中タイマー")
        tap(app.buttons["やめる"])
        tap(app.buttons["写真で記録(見本)"])
        sleep(1)
        snap("50-写真で記録")
        tap(app.buttons["閉じる"].firstMatch)
        scrollTo(app.buttons["はなまるを出す(7日連続)"])
        tap(app.buttons["はなまるを出す(7日連続)"])
        waitFor(app.staticTexts["7日連続"])
        Thread.sleep(forTimeInterval: 1.8)
        snap("51-はなまる-7日")
        tap(app.buttons["閉じる"].firstMatch)
        tap(app.buttons["週のふり返りを開く"])
        waitFor(app.buttons["相棒に手紙を書いてもらう"])
        tap(app.buttons["相棒に手紙を書いてもらう"])
        waitFor(anyElement(containing: "小さな発見"), timeout: 20)
        snap("52-週のふり返り-手紙")
        tap(app.buttons["あとで"])
        scrollTo(app.staticTexts["合 格 証"])
        snap("53-合格証-見本")

        // S-07 緊急解除・S-08 一時停止
        tap(app.tabBars.buttons["今日"])
        scrollTo(app.buttons["緊急解除"])
        tap(app.buttons["緊急解除"])
        waitFor(app.buttons["緊急解除を申請する"])
        snap("54-緊急解除")
        tap(app.buttons["閉じる"].firstMatch)
        tap(app.buttons["一時停止"])
        sleep(1)
        snap("55-一時停止")
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
        snap("56-クイックアクション")
        quickCheckIn.tap()
        waitFor(app.navigationBars["チェックイン"], timeout: 15)
        snap("57-クイックアクションから")
    }

    /// 押せる(ほかのものに隠れていない)最初の要素
    @MainActor
    private func firstHittable(_ query: XCUIElementQuery) -> XCUIElement {
        for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
            return element
        }
        return query.firstMatch
    }

    /// 画面の中(ナビゲーションバーとタブバーのあいだ)に、まるごと見えている最初の要素
    @MainActor
    private func visible(_ query: XCUIElementQuery) -> XCUIElement {
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
        let bottom = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
        for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
            if element.frame.minY >= top && element.frame.maxY <= bottom { return element }
        }
        return query.firstMatch
    }

    /// 文字を入れる欄(縦に伸びる TextField は、TextField としても TextView としても見えることがあるので両方を探す)。
    /// 押したあとは、欄ではなくアプリに打ち込む(欄の見え方が変わっても入る)
    @MainActor
    private func textInput() -> XCUIElement {
        let types = [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue]
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType IN %@", types)).firstMatch
    }

    /// 欄を押して、キーボードが出るまで待つ(スクロールの直後に押すと、スクロールを止めるだけで欄に入らないことがある)
    @MainActor
    private func focus(_ element: XCUIElement) -> Bool {
        Thread.sleep(forTimeInterval: 0.8)   // スクロールが止まるのを待つ
        for _ in 0..<3 {
            guard element.exists else { return false }
            // 欄の上のほうを押す(下のほうはボタンの帯に重なることがある)
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 2.5) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// 文を含む要素(相棒の書き込みは、まとめて読み上げる1つの要素になるので種類を問わない)
    @MainActor
    private func anyElement(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
