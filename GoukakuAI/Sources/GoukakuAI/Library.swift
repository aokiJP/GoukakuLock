import Foundation

/// 体験帳の1項目(AIが使えないとき・AIの出力が使えなかったときに出す)
public struct LibraryItem: Sendable, Equatable, Identifiable {
    public enum Energy: Int, Sendable { case low = 0, mid = 1, high = 2 }

    /// 出してよい時間帯
    public enum When: Sendable, Equatable {
        case any
        case morning
        case daytime      // 朝〜夕方
        case evening      // 夕方
        case night        // 夜・深夜
        case notLateNight

        func allows(_ tod: TimeOfDay) -> Bool {
            switch self {
            case .any: return true
            case .morning: return tod == .morning
            case .daytime: return tod == .morning || tod == .daytime || tod == .evening
            case .evening: return tod == .evening
            case .night: return tod == .night || tod == .lateNight
            case .notLateNight: return tod != .lateNight
            }
        }
    }

    public var id: String
    public var category: ExperienceCategory
    public var title: String
    public var line: String
    public var step: String
    public var minutes: Int
    public var place: Place
    public var energy: Energy
    public var when: When
    /// 興味の手がかり(「この人について」や続けていることに含まれていたら優先)
    public var tags: [String]

    public var duration: DurationBucket { .nearest(minutes: minutes) }

    public func draft() -> ExperienceDraft {
        ExperienceDraft(title: title, line: line, firstStep: step, duration: duration,
                        category: category, origin: .library(id))
    }
}

private func L(_ id: String, _ category: ExperienceCategory, _ title: String, _ line: String, _ step: String,
               _ minutes: Int, _ place: Place, _ energy: LibraryItem.Energy = .low,
               when: LibraryItem.When = .any, tags: [String] = []) -> LibraryItem {
    LibraryItem(id: id, category: category, title: title, line: line, step: step, minutes: minutes,
                place: place, energy: energy, when: when, tags: tags)
}

/// 内蔵の体験帳(96項目)。お金を使わず、安全で、今日すぐ小さく始められるものだけ
public enum ExperienceLibrary {
    public static let items: [LibraryItem] = [
        // 学ぶ
        L("learn-word", .learn, "知らない言葉を1つ辞書で引く", "意味がわかると、いつもの景色の見え方が少し変わるかも", "最近気になった言葉を1つ思い出す", 5, .anywhere, tags: ["言葉", "読書", "国語"]),
        L("learn-why", .learn, "身の回りの「なぜ」を1つ調べる", "当たり前だと思っていたことに、意外な理由が見つかるかも", "目の前の物を1つ選んで、なぜこの形なのか考える", 15, .anywhere),
        L("learn-lyrics", .learn, "好きな曲の歌詞を英語で読む", "知っている曲が、別の言葉でどう響くかに出会えるかも", "好きな曲を1つ決めて、英語の歌詞を探す", 15, .anywhere, tags: ["英語", "語学", "音楽", "単語"]),
        L("learn-onesentence", .learn, "覚えた言葉で今日を1文にする", "自分の一日を別の言葉で言えると、言葉が自分のものになるかも", "今日いちばん印象に残った場面を1つ選ぶ", 5, .anywhere, tags: ["英語", "語学", "単語", "英単語", "TOEIC", "英検"]),
        L("learn-streetview", .learn, "行ったことのない国の街を地図で歩く", "画面の向こうの暮らしに、思わぬ共通点が見つかるかも", "地図アプリで、名前だけ知っている街を開く", 15, .home, tags: ["旅", "地理", "英語"]),
        L("learn-library", .learn, "図書館で普段行かない棚を眺める", "興味の外の背表紙に、次の好奇心が隠れているかも", "近くの図書館が開いている時間を調べる", 30, .outside, .mid, when: .daytime, tags: ["読書", "本"]),
        L("learn-teach", .learn, "最近知ったことを人に話してみる", "説明してみると、自分がどこまでわかっているかが見えてくるかも", "話したいことを1つ、メモに一行で書く", 15, .anywhere, .mid, tags: ["勉強", "資格", "試験"]),
        L("learn-origin", .learn, "好きな言葉の語源をたどる", "言葉が生まれた道すじに、小さな物語があるかも", "好きな言葉を1つ思い浮かべる", 5, .anywhere, tags: ["言葉", "英語", "単語", "語学"]),
        L("learn-moon", .learn, "今日の月の形を調べてから見上げる", "知ってから見ると、いつもの空が少し近くなるかも", "今日の月の形を調べる", 5, .anywhere, when: .notLateNight, tags: ["自然", "空"]),
        L("learn-documentary", .learn, "短いドキュメンタリーを1本見る", "知らない世界の誰かの毎日が、自分の毎日を照らすかも", "気になるテーマを1つ決める", 30, .home, tags: ["映画", "動画"]),
        L("learn-plant", .learn, "道ばたの草花の名前を調べる", "名前を知ると、いつもの道が急ににぎやかになるかも", "見かけた花や葉を1つ写真に撮る", 15, .outside, when: .daytime, tags: ["自然", "写真", "散歩"]),
        L("learn-examiner", .learn, "1問だけ、出題者の気持ちで解く", "なぜこの問題なのかを考えると、問題が会話のように見えてくるかも", "最近解いた問題を1つ選び直す", 15, .anywhere, tags: ["過去問", "試験", "資格", "問題", "テスト"]),

        // からだ
        L("body-breath", .body, "1分だけ呼吸の数をかぞえる", "体の中の静かなリズムに気づけるかも", "楽な姿勢で目を閉じる", 5, .anywhere),
        L("body-shoulder", .body, "肩と首をゆっくり回す", "どこが固くなっていたか、体が教えてくれるかも", "肩を耳に近づけて、すとんと落とす", 5, .anywhere, tags: ["勉強", "仕事"]),
        L("body-onestation", .body, "いつもより一駅分歩く", "乗り物では通り過ぎていた景色に出会えるかも", "次に出かけるとき、一つ手前で降りる道を調べる", 30, .outside, .mid, when: .daytime, tags: ["散歩", "運動"]),
        L("body-dance", .body, "好きな曲1曲ぶん体を動かす", "音に合わせて動くと、気分が少し軽くなるかも", "いちばん好きな曲を1曲選ぶ", 5, .home, .mid, when: .notLateNight, tags: ["音楽", "運動", "ダンス"]),
        L("body-barefoot", .body, "はだしで床の感触を確かめる", "足の裏から、いつもと違う手ざわりが届くかも", "靴下を脱いで、ゆっくり歩いてみる", 5, .home),
        L("body-stairs", .body, "階段を一段ずつ味わって上る", "足の使い方を意識すると、体の動きのしくみが見えてくるかも", "次に階段を見かけたら、ゆっくり上る", 5, .outside, .mid, tags: ["運動", "筋トレ"]),
        L("body-stretch-night", .body, "寝る前に体を伸ばして一日をほどく", "伸びた分だけ、一日の力みが抜けていくかも", "布団の上で、両手をばんざいに伸ばす", 5, .home, when: .night),
        L("body-posture", .body, "背すじを伸ばして3分過ごす", "姿勢が変わると、気分の向きも少し変わるかも", "いすに深く座り直す", 5, .anywhere, tags: ["勉強", "仕事"]),
        L("body-footsteps", .body, "足音を聞きながら歩く", "歩く速さで、今日の自分の調子がわかるかも", "次に歩くとき、足音に耳を向ける", 15, .outside, .mid, when: .notLateNight, tags: ["散歩"]),
        L("body-water", .body, "水を一杯、ゆっくり飲む", "冷たさが体をめぐる感じに気づけるかも", "コップに水をくむ", 5, .anywhere),
        L("body-radio", .body, "ラジオ体操を思い出しながら動く", "子どものころの体の記憶がよみがえるかも", "最初の動きを思い出してみる", 5, .home, .mid, when: .notLateNight, tags: ["運動"]),
        L("body-squat-song", .body, "好きな曲のサビの間だけスクワット", "音楽といっしょなら、体を動かす時間が短く感じるかも", "サビが始まるところを確かめる", 5, .home, .mid, when: .notLateNight, tags: ["運動", "筋トレ", "音楽", "トレーニング"]),

        // つくる
        L("make-fridge", .make, "冷蔵庫の残りで名前のない一品", "決まったレシピがないと、思いがけない組み合わせに出会えるかも", "冷蔵庫を開けて、目についた材料を3つ選ぶ", 30, .home, .mid, when: .notLateNight, tags: ["料理"]),
        L("make-sky-words", .make, "今日の空を言葉だけでスケッチする", "色の名前を探すうちに、空がいつもより細かく見えてくるかも", "窓の外の空を10秒見つめる", 5, .anywhere, when: .notLateNight, tags: ["言葉", "書く", "空"]),
        L("make-haiku", .make, "今日を5・7・5にしてみる", "17音におさめると、一日のいちばん大事なところが見えるかも", "今日いちばん心に残った場面を1つ選ぶ", 5, .anywhere, tags: ["言葉", "書く", "国語"]),
        L("make-photo-title", .make, "好きな写真に題名をつける", "名前をつけると、その瞬間がもう一度動き出すかも", "写真アプリで、気に入っている1枚を開く", 5, .anywhere, tags: ["写真"]),
        L("make-letter", .make, "出さなくてもいい手紙を書く", "書いてみると、伝えたかったことの形がわかるかも", "宛先の人を1人思い浮かべる", 15, .home, tags: ["書く", "手紙"]),
        L("make-line-drawing", .make, "目の前の物を1つ、線だけで描く", "よく見るほど、知っていたつもりの形が新しく見えるかも", "紙とペンを用意して、物を1つ選ぶ", 15, .anywhere, tags: ["絵", "デザイン"]),
        L("make-melody", .make, "今日の気分を短いメロディにする", "言葉にならない気持ちも、音なら出せるかも", "鼻歌で、今の気分を3つの音にしてみる", 5, .anywhere, tags: ["音楽", "楽器", "歌"]),
        L("make-playlist", .make, "今日の自分のプレイリストを3曲で作る", "選んだ曲の並びに、今の自分が映るかも", "今の気分に合う曲を1曲思い出す", 15, .anywhere, tags: ["音楽"]),
        L("make-origami", .make, "紙を1枚、何かの形に折る", "指先が覚えている形が、ふと出てくるかも", "手元の紙を1枚、正方形にする", 15, .home, tags: ["工作"]),
        L("make-recipe-card", .make, "得意な料理の作り方を書き残す", "書き出すと、自分なりのこつに気づけるかも", "いちばんよく作る料理を1つ決める", 15, .home, tags: ["料理", "書く"]),
        L("make-code-note", .make, "書いたコードに未来の自分への一言を残す", "少し先の自分を思うと、作っているものの見え方が変わるかも", "最近書いたコードを1つ開く", 5, .anywhere, tags: ["プログラミング", "コード", "開発", "アプリ"]),
        L("make-four-panel", .make, "今日の出来事を4コマにする", "絵にすると、出来事のおかしみが見えてくるかも", "紙に四角を4つ描く", 15, .anywhere, tags: ["絵", "マンガ", "書く"]),

        // ひと
        L("people-message", .people, "しばらく話していない人に一言送る", "短いひとことが、思いがけない会話の始まりになるかも", "最近ふと思い出した人を1人選ぶ", 5, .anywhere, when: .notLateNight),
        L("people-best-today", .people, "身近な人に今日よかったことを聞く", "相手の一日をのぞくと、自分の一日も少し明るくなるかも", "次に顔を合わせたとき、聞いてみる", 5, .home, when: .notLateNight, tags: ["家族"]),
        L("people-thanks", .people, "お店の人に、お礼をひとこと足す", "ひとことで、その場の空気が少しやわらぐかも", "次の窓口で、目を見て伝える", 5, .outside, when: .notLateNight),
        L("people-three-goods", .people, "友だちのいいところを3つ書く", "書いた言葉を1つ伝えると、自分にも返ってくるかも", "友だちを1人思い浮かべて、1つ目を書く", 15, .anywhere, tags: ["友だち"]),
        L("people-old-story", .people, "家族に昔の話を1つ聞く", "知っているつもりの人の、知らない顔に出会えるかも", "「子どものころ好きだった遊びは?」と聞いてみる", 15, .home, .mid, when: .notLateNight, tags: ["家族"]),
        L("people-call", .people, "声で話したい人に電話をかける", "文字より、声のほうが伝わることがあるかも", "電話してもいい時間か、短く聞いてみる", 15, .anywhere, .mid, when: .daytime),
        L("people-recommend", .people, "好きな本や曲を誰かにすすめる", "好きなものを言葉にすると、自分の好みの形が見えてくるかも", "すすめたいものを1つ決める", 5, .anywhere, tags: ["読書", "音楽", "映画"]),
        L("people-listen", .people, "誰かの話を最後までさえぎらずに聞く", "ただ聞くだけで、相手の表情が変わるのが見えるかも", "次の会話で、あいづちだけにしてみる", 15, .anywhere, .mid, when: .notLateNight),
        L("people-greeting", .people, "いつもより少し大きな声であいさつする", "あいさつ一つで、その日の空気が変わるかも", "次に会った人に、先に声をかける", 5, .anywhere, when: .notLateNight),
        L("people-old-photos", .people, "昔の写真を誰かと見返す", "写真の向こうの話が、たくさん出てくるかも", "スマホの写真を、何年か前までさかのぼる", 15, .anywhere, tags: ["写真", "家族", "友だち"]),
        L("people-tea-for", .people, "誰かのために、お茶を一杯いれる", "相手を思って手を動かすと、自分の気持ちも温かくなるかも", "相手の好きな飲み物を思い出す", 5, .home, when: .notLateNight, tags: ["家族"]),
        L("people-explain-work", .people, "今日動いたものを誰かに一言で話す", "一言にまとめると、自分のしたことの手ごたえが増すかも", "話す相手を1人決める", 5, .anywhere, tags: ["プログラミング", "仕事", "開発"]),

        // そと
        L("out-other-corner", .outside, "いつもと逆の角を曲がって歩く", "いつもの町に、まだ知らない景色が見つかるかも", "玄関を出て、いつもと逆に曲がる", 15, .outside, .mid, when: .daytime, tags: ["散歩"]),
        L("out-clouds", .outside, "雲の形に名前をつける", "見上げるだけで、頭の中に少し風が通るかも", "空を見上げて、いちばん大きな雲を探す", 5, .anywhere, when: .daytime, tags: ["空", "自然"]),
        L("out-park-sounds", .outside, "公園のベンチで聞こえる音を数える", "耳をすますと、静かだと思っていた場所がにぎやかに感じるかも", "座れる場所を見つけて、目を閉じる", 15, .outside, when: .daytime, tags: ["自然", "散歩"]),
        L("out-sunset", .outside, "夕方の光が変わるのを見届ける", "空の色が移る数分間に、一日の区切りを感じられるかも", "西の空が見える場所に出る", 15, .anywhere, when: .evening, tags: ["空", "自然", "写真"]),
        L("out-morning-air", .outside, "朝の空気を吸いに外へ出る", "朝のにおいで、体がゆっくり目を覚ますかも", "窓を開けるか、玄関の外に出る", 5, .anywhere, when: .morning),
        L("out-my-tree", .outside, "近所の木を1本「自分の木」にする", "同じ木を見続けると、季節の動きがわかるかも", "毎日通る道で、気になる木を1本選ぶ", 5, .outside, when: .daytime, tags: ["自然", "散歩"]),
        L("out-shadow", .outside, "自分の影の長さを見る", "影の長さで、時間と太陽の位置が感じられるかも", "日の当たる場所に立つ", 5, .outside, when: .daytime),
        L("out-no-map", .outside, "地図を見ないで、ひと回りして帰る", "迷いそうで迷わない、小さな冒険になるかも", "帰り道の目印を1つ決めてから出る", 30, .outside, .mid, when: .daytime, tags: ["散歩", "旅"]),
        L("out-bright-star", .outside, "夜空で明るい星を1つ探す", "遠い光を見ていると、悩みの大きさが少し変わるかも", "ベランダや窓から、いちばん明るい星を探す", 5, .anywhere, when: .night, tags: ["空", "自然"]),
        L("out-new-park", .outside, "行ったことのない公園まで歩く", "知らない公園には、知らない人の毎日があるかも", "地図で近くの公園を1つ探す", 30, .outside, .mid, when: .daytime, tags: ["散歩", "自然"]),
        L("out-people-flow", .outside, "広場で行き交う人をながめる", "人の流れを見ていると、町のリズムが聞こえてくるかも", "座れる場所を見つける", 15, .outside, when: .daytime),
        L("out-color-hunt", .outside, "外で同じ色の物を5つ探す", "色を決めて歩くと、町がゲームの盤になるかも", "今日の色を1つ決める", 15, .outside, .mid, when: .daytime, tags: ["写真", "散歩"]),

        // こころ
        L("mind-three-good", .mind, "今日うれしかったことを3つ書く", "小さなことほど、書くと大きく感じられるかも", "1つ目は、どんなに小さなことでもいい", 5, .anywhere),
        L("mind-tea", .mind, "お茶の香りが消えるまで味わう", "香りの移り変わりに、時間がゆっくり流れるかも", "お湯をわかす", 15, .home),
        L("mind-window", .mind, "スマホを置いて窓の外をながめる", "何もしない時間に、ふと考えが浮かぶかも", "スマホを別の部屋に置く", 5, .home),
        L("mind-self-note", .mind, "がんばった自分に一行のメモを書く", "自分にかける言葉が、少しやさしくなるかも", "今週がんばったことを1つ思い出す", 5, .anywhere),
        L("mind-one-song", .mind, "ほかのことをせずに1曲だけ聴く", "ながら聴きでは気づかなかった音が聞こえるかも", "イヤホンをして、目を閉じる", 5, .anywhere, tags: ["音楽"]),
        L("mind-worry-paper", .mind, "気になっていることを紙に書き出す", "外に出してみると、思っていたより小さく見えるかも", "紙の真ん中に、今いちばん気になることを書く", 5, .anywhere),
        L("mind-one-light", .mind, "明かりを1つだけにして過ごす", "暗さが、気持ちを内側に向けてくれるかも", "照明を1つだけ残して消す", 15, .home, when: .night),
        L("mind-childhood", .mind, "子どものころ好きだった物を思い出す", "忘れていた「好き」が、今の自分につながっているかも", "小学生のころの休みの日を思い出す", 5, .anywhere),
        L("mind-bath", .mind, "お風呂で一日を巻き戻す", "湯気の中で思い出すと、一日がやわらかく見えるかも", "湯船で、朝からの出来事を順番に思い出す", 15, .home, when: .night),
        L("mind-old-thing", .mind, "長く使っている物に「ありがとう」を言う", "物との付き合いの長さに、自分の歩みが見えるかも", "いちばん長く使っている物を探す", 5, .home),
        L("mind-future-self", .mind, "1年後の自分に一行だけ書く", "未来の自分を思うと、今日の選び方が少し変わるかも", "「1年後のわたしへ」と書き出す", 5, .anywhere, tags: ["試験", "資格", "目標"]),
        L("mind-first-bite", .mind, "ひと口目をゆっくり味わう", "噛むほど、知らなかった味が出てくるかも", "次の食事の最初のひと口に集中する", 5, .anywhere, tags: ["料理"]),

        // くらし
        L("live-desk", .living, "机の上の物を1つだけ減らす", "1つ減ると、目に入る景色が少しすっきりするかも", "机の上で、いちばん使っていない物を選ぶ", 5, .home, tags: ["勉強", "仕事"]),
        L("live-drink", .living, "いつもの飲み物をていねいにいれる", "手順をゆっくりにすると、香りの違いに気づけるかも", "お湯の温度を気にしてみる", 15, .home),
        L("live-shoes", .living, "靴をみがく", "足元が整うと、明日の一歩が少し軽くなるかも", "いちばんよくはく靴を出す", 15, .home),
        L("live-tomorrow-joy", .living, "明日の小さな楽しみを1つ決める", "楽しみが1つあると、朝の目覚めが変わるかも", "明日の予定を思い浮かべる", 5, .home, when: .night),
        L("live-air", .living, "部屋の空気を入れかえる", "新しい空気が入ると、部屋の印象が変わるかも", "窓を2か所開ける", 5, .home, when: .notLateNight),
        L("live-plant", .living, "部屋の植物の葉を1枚ずつ見る", "小さな変化に気づくと、植物との距離が近くなるかも", "葉の裏までのぞいてみる", 5, .home, tags: ["植物", "自然"]),
        L("live-song-tidy", .living, "好きな曲1曲ぶんだけ片づける", "曲が終わるころ、思ったより片づいているかも", "曲を1つ流す", 5, .home, .mid, when: .notLateNight, tags: ["音楽"]),
        L("live-move-one", .living, "部屋の物を1つ、置き場所を変える", "置き場所が変わるだけで、部屋が新しく見えるかも", "動かせそうな物を1つ選ぶ", 5, .home),
        L("live-new-dish", .living, "いつもと違う器で食事をする", "器が変わると、同じ料理も違って見えるかも", "普段使わない器を1つ出す", 15, .home, when: .notLateNight, tags: ["料理"]),
        L("live-dim", .living, "寝る前に明かりを1段暗くする", "光を落とすと、体が夜の準備を始めるかも", "寝る30分前に、明かりを1段落とす", 30, .home, when: .night),
        L("live-fridge-look", .living, "冷蔵庫を見て、食べたい物を考える", "中身を知ると、台所に立つのが少し楽しみになるかも", "冷蔵庫の一段目から見ていく", 5, .home, when: .notLateNight, tags: ["料理"]),
        L("live-bag", .living, "かばんの中身を全部出して並べる", "持ち歩いている物に、今の暮らしが表れているかも", "机の上に、かばんの中身を並べる", 5, .home),

        // はじめて
        L("first-genre", .first, "普段聴かないジャンルの曲を1曲聴く", "知らない音の中に、好きになる何かがあるかも", "聴いたことのないジャンル名で探す", 5, .anywhere, tags: ["音楽"]),
        L("first-other-hand", .first, "利き手と反対の手で名前を書く", "慣れない手の動きに、子どものころの感覚がよみがえるかも", "紙とペンを、反対の手に持つ", 5, .anywhere),
        L("first-shop-front", .first, "入ったことのない近所の店の前まで行く", "店の前に立つだけで、町の新しい一面が見えるかも", "いつも素通りしている店を1つ思い出す", 15, .outside, .mid, when: .daytime, tags: ["散歩"]),
        L("first-tool", .first, "使ったことのない道具の使い方を調べる", "知らない道具の向こうに、別の暮らし方が見えるかも", "家の中で、使い方を知らない物を探す", 15, .home),
        L("first-drawer", .first, "いちばん長く開けていない引き出しを開ける", "忘れていた物との再会が待っているかも", "引き出しを1つ選ぶ", 5, .home),
        L("first-new-route", .first, "いつもと違う道で帰る", "遠回りの分だけ、新しい景色が手に入るかも", "帰り道に、1本だけ違う道を選ぶ", 15, .outside, .mid, when: .daytime, tags: ["散歩"]),
        L("first-home-dish", .first, "行ったことのない国の家庭料理を調べる", "料理を通して、その国の毎日が少し見えるかも", "気になる国を1つ選ぶ", 15, .anywhere, tags: ["料理", "旅", "語学"]),
        L("first-thanks-lang", .first, "知らない言語で「ありがとう」を覚える", "たった一言で、その言葉を話す人が少し近くなるかも", "気になる国の言葉を1つ選ぶ", 5, .anywhere, tags: ["語学", "英語", "旅"]),
        L("first-eyes-closed", .first, "目を閉じて、部屋の中を少し歩く", "見えないと、音や手ざわりがくっきりしてくるかも", "安全な短い距離を決めてから、ゆっくり歩く", 5, .home),
        L("first-podcast", .first, "知らない分野の番組を1本聴く", "聞いたことのない話に、意外な面白さがあるかも", "普段聴かないテーマで探す", 30, .anywhere),
        L("first-recommend", .first, "人のおすすめを1つ試してみる", "自分では選ばないものに、新しい「好き」が隠れているかも", "最近すすめられたものを思い出す", 15, .anywhere),
        L("first-early-light", .first, "いつもより少し早く朝の光を浴びる", "早い朝に、いつもと違う町の顔が見えるかも", "起きたらまずカーテンを開ける", 15, .anywhere, when: .morning),
    ]

    /// 続けていること(コミット)を体験に変える工夫。コミットの言葉で選ぶ
    public static let reframes: [(keywords: [String], items: [LibraryItem])] = [
        (["英単語", "単語", "英語", "TOEIC", "英検", "語学", "言語", "英会話"],
         byIDs("learn-onesentence", "learn-origin", "learn-lyrics")),
        (["過去問", "問題", "試験", "資格", "テスト", "模試"],
         byIDs("learn-examiner") + [
            L("reframe-nickname", .make, "まちがえた問題にあだ名をつける", "名前がつくと、次に会ったときにすぐ気づけるかも", "最近まちがえた問題を1つ開く", 5, .anywhere),
         ]),
        (["集中", "勉強", "テキスト", "参考書", "学習", "授業"],
         byIDs("live-desk") + [
            L("reframe-oneline", .make, "終わりに、わかったことを一行で書く", "一行にすると、今日の自分の前進が見えるかも", "ノートのいちばん下に一行ぶん空けておく", 5, .anywhere),
         ]),
        (["読書", "本", "ページ", "小説"], [
            L("reframe-copy-line", .make, "気に入った1文を書き写す", "書き写すと、文の手ざわりがわかるかも", "読んだページから、1文に印をつける", 5, .anywhere),
            L("reframe-book-map", .learn, "本に出てきた場所を地図で探す", "物語の舞台が、急に近くに感じられるかも", "本に出てきた地名を1つ選ぶ", 15, .anywhere),
        ]),
        (["筋トレ", "運動", "ジム", "ランニング", "ストレッチ", "スクワット", "腕立て", "トレーニング"],
         byIDs("body-squat-song") + [
            L("reframe-body-thanks", .body, "終わったら、いちばん効いた場所に手を当てる", "体の声を聞くと、明日の体の使い方が変わるかも", "動いたあと、深呼吸を1回する", 5, .anywhere),
         ]),
        (["楽器", "ピアノ", "ギター", "練習", "バイオリン", "ドラム", "歌"], [
            L("reframe-mood-bar", .make, "今日の気分を1小節で弾く", "練習曲の合間に、自分の音が見つかるかも", "楽器を手に取って、最初の一音を決める", 5, .home),
            L("reframe-first-note", .make, "好きな曲の最初の一音を探す", "耳で探した音は、指がよく覚えているかも", "好きな曲を1曲流す", 15, .home),
        ]),
        (["プログラミング", "コード", "開発", "アプリ", "Swift", "Python"],
         byIDs("make-code-note", "people-explain-work")),
        (["料理", "自炊", "ごはん", "お弁当"],
         byIDs("make-fridge", "make-recipe-card")),
        (["散歩", "歩", "ウォーキング"],
         byIDs("out-other-corner", "body-footsteps")),
    ]

    /// どのコミットにも使える工夫
    public static let genericReframes: [LibraryItem] = [
        L("reframe-after-line", .mind, "終わったら、一行だけ感想を書く", "一行の感想が、続けてきた道のりの記録になるかも", "記録の一言に、感じたことを足す", 5, .anywhere),
        L("reframe-imagine", .mind, "始める前に、終わったあとの自分を想像する", "終わったときの気分を先に味わうと、始めの一歩が軽くなるかも", "目を閉じて、終わった瞬間を思い浮かべる", 5, .anywhere),
    ]

    public static func item(_ id: String) -> LibraryItem? {
        items.first { $0.id == id }
    }

    /// id から項目を集める(見つからない id は飛ばす)
    static func byIDs(_ ids: String...) -> [LibraryItem] {
        ids.compactMap(item)
    }

    // MARK: 選ぶ

    /// 今の様子に合う体験を count 個選ぶ(種類が重ならないように)
    public static func pick(for context: CompanionContext, count: Int, avoid: Set<String>, seed: UInt64,
                            angles: [ExperienceCategory]? = nil) -> [ExperienceDraft] {
        let tod = context.timeOfDay
        let fits = items.filter { item in
            guard item.when.allows(tod), context.budget.allows(item.duration) else { return false }
            guard !avoid.contains(item.title) else { return false }
            if context.mood == .tired && item.energy != .low { return false }
            switch (context.place, item.place) {
            case (.home, .outside): return false
            case (.outside, .home): return false
            default: return true
            }
        }
        let keywords = (context.notes + context.commits).joined(separator: " ")
        var rng = SeededGenerator(seed: seed)
        func score(_ item: LibraryItem) -> Double {
            var s = Double.random(in: 0..<1, using: &rng)
            if item.tags.contains(where: { keywords.contains($0) }) { s += 1.5 }
            s += Double(max(-3, min(3, context.categoryAffinity[item.category] ?? 0))) * 0.3
            if context.mood == .energetic && item.energy != .low { s += 0.5 }
            return s
        }
        let order = angles ?? AnglePlanner.angles(for: context, count: count, seed: seed)
        var picked: [ExperienceDraft] = []
        var usedIDs = Set<String>()
        for angle in order where picked.count < count {
            let candidates = fits.filter { $0.category == angle && !usedIDs.contains($0.id) }
            if let best = candidates.map({ ($0, score($0)) }).max(by: { $0.1 < $1.1 })?.0 {
                picked.append(best.draft())
                usedIDs.insert(best.id)
            }
        }
        // 足りなければ、種類を問わず
        if picked.count < count {
            let rest = fits.filter { !usedIDs.contains($0.id) && !picked.map(\.category).contains($0.category) }
                .map { ($0, score($0)) }.sorted { $0.1 > $1.1 }
            for (item, _) in rest where picked.count < count {
                picked.append(item.draft())
                usedIDs.insert(item.id)
            }
        }
        if picked.count < count {
            let any = items.filter { !usedIDs.contains($0.id) && !avoid.contains($0.title) && $0.when.allows(tod) }
            for item in any.shuffled(using: &rng) where picked.count < count {
                picked.append(item.draft())
                usedIDs.insert(item.id)
            }
        }
        return picked
    }

    /// コミットを体験に変える工夫を選ぶ
    public static func reframes(for commit: String, count: Int, avoid: Set<String>) -> [ExperienceDraft] {
        var result: [LibraryItem] = []
        for entry in reframes where entry.keywords.contains(where: { commit.contains($0) }) {
            result.append(contentsOf: entry.items)
        }
        result.append(contentsOf: genericReframes)
        var seen = Set<String>()
        return result.filter { !avoid.contains($0.title) && seen.insert($0.id).inserted }.prefix(count).map { $0.draft() }
    }

    /// 「いつかの体験」の芽(体験帳から、少し大きめのもの)
    public static func someday(for context: CompanionContext, angle: ExperienceCategory, avoid: Set<String>,
                               seed: UInt64) -> ExperienceDraft? {
        var rng = SeededGenerator(seed: seed)
        let candidates = somedayItems.filter { $0.category == angle && !avoid.contains($0.title) }
        return (candidates.isEmpty ? somedayItems.filter { !avoid.contains($0.title) } : candidates)
            .randomElement(using: &rng)?.draft()
    }

    /// いつかの体験(大きめ。体験帳の版)
    public static let somedayItems: [LibraryItem] = [
        L("someday-sunrise", .outside, "日の出を見に、少し遠くまで行く", "暗い空が明るくなる時間を、最初から最後まで見届けられるかも", "日の出の時刻と、見えそうな場所を調べる", 240, .outside),
        L("someday-language-trip", .learn, "覚えた言葉が通じる国を歩く", "教科書の言葉が、誰かとの会話に変わる瞬間に出会えるかも", "行ってみたい国の名前を1つ書く", 240, .anywhere),
        L("someday-cook-feast", .make, "大切な人のために、一日かけて料理する", "時間をかけた分だけ、食卓の会話が長くなるかも", "作ってみたい料理を1つ選ぶ", 240, .home),
        L("someday-reunion", .people, "昔の友だちと会う日をつくる", "会わなかった時間の分だけ、話すことがたくさんあるかも", "会いたい人を1人思い浮かべる", 240, .anywhere),
        L("someday-mountain", .body, "自分の足で、小さな山の頂上に立つ", "登った分だけ、見下ろす景色が自分のものになるかも", "近くの低い山を1つ調べる", 240, .outside),
        L("someday-quiet-day", .mind, "何も予定を入れない一日を過ごす", "空白の一日に、自分が本当にしたいことが浮かんでくるかも", "カレンダーに、空白の日を1つ決める", 240, .anywhere),
        L("someday-new-skill", .first, "まったく知らない習い事の体験に行く", "ゼロから始める感覚を、もう一度味わえるかも", "気になる習い事を3つ書き出す", 240, .anywhere),
        L("someday-home-change", .living, "部屋の模様替えを一日かけてする", "家具の位置が変わると、毎日の動き方まで変わるかも", "部屋の簡単な見取り図を描く", 240, .home),
    ]

    // MARK: ふり返り(AIなし)

    static let questions: [ExperienceCategory: [String]] = [
        .learn: ["知ったことの中で、誰かに話したくなったのはどこでしたか?", "次に調べてみたくなったことはありますか?"],
        .body: ["体のどこが一番よろこんでいましたか?", "やる前とあとで、体の感じはどう変わりましたか?"],
        .make: ["できたものに名前をつけるとしたら、何にしますか?", "次につくるなら、どこを変えてみたいですか?"],
        .people: ["相手のどんな表情が印象に残りましたか?", "次は誰と、どんな話をしてみたいですか?"],
        .outside: ["いちばん印象に残った音や景色は何でしたか?", "次はどの道を歩いてみたいですか?"],
        .mind: ["その時間のあと、気持ちはどんなふうに変わりましたか?", "また同じ時間をとるなら、いつがいいですか?"],
        .living: ["やってみて、暮らしのどこが少し変わりましたか?", "次に整えたくなった場所はありますか?"],
        .first: ["はじめてやってみて、いちばん意外だったことは何でしたか?", "もう一度やるとしたら、何を変えてみますか?"],
    ]

    /// AIなしのふり返り(書いたことにふれて、問いを1つ)
    public static func reflection(title: String, note: String, feeling: Feeling?,
                                  category: ExperienceCategory?) -> ReflectionDraft {
        var reply = "「\(title)」をやってみたんですね。"
        switch feeling {
        case .fun?: reply += "たのしめた時間になったようで、うれしいです。"
        case .discovery?: reply += "何か新しいことに気づけたようですね。"
        case .calm?: reply += "おだやかな時間になったようですね。"
        case .moved?: reply += "うれしい気持ちが伝わってきます。"
        case .hard?: reply += "むずかしさも含めて、ちゃんと体験したことが残りました。"
        case .soso?, nil: reply += "ふつうの日のふつうの体験も、大切な記録です。"
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let snippet = trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
            reply += "「\(snippet)」と書いてくれたこと、ここに残しておきます。"
        }
        let bank = questions[category ?? .mind] ?? questions[.mind]!
        let index = Int(stableHash(title) % UInt64(bank.count))
        return ReflectionDraft(reply: reply, question: bank[index], noteCandidate: nil, fromAI: false)
    }

    // MARK: 週の手紙(AIなし)

    public static func letter(experiences: [(title: String, category: ExperienceCategory)], achievedDays: Int,
                              context: CompanionContext, seed: UInt64) -> String {
        var text: String
        if experiences.isEmpty {
            text = "この1週間は、体験の記録がない静かな週でした。休むことも、大切な体験のひとつです。"
        } else {
            var counts: [ExperienceCategory: Int] = [:]
            for e in experiences { counts[e.category, default: 0] += 1 }
            let top = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue }!.key
            text = "この1週間に、\(experiences.count)つの体験をしました。いちばん多かったのは「\(top.label)」の体験です。"
            if let last = experiences.first {
                text += "「\(last.title)」は、どんな時間でしたか。"
            }
        }
        if achievedDays > 0 {
            text += "続けていることにも、ちゃんと向き合った週でした。"
        }
        let explored = Set(experiences.map(\.category))
        let fresh = ExperienceCategory.allCases.filter { !explored.contains($0) }
        if let next = pick(for: context, count: 1, avoid: Set(experiences.map(\.title)), seed: seed,
                           angles: fresh.isEmpty ? nil : [fresh[Int(seed % UInt64(fresh.count))]]).first {
            text += "来週は「\(next.title)」はどうでしょう。\(next.line)。"
        }
        return text
    }

    /// 体験の記録から、ルールで気づきを書く(AIがないとき)
    public static func insight(experiences: [ExperienceMemo], unexplored: [ExperienceCategory]) -> String {
        guard !experiences.isEmpty else {
            return "まだ体験の記録がありません。やってみた体験が増えると、相棒が気づいたことを書きます。"
        }
        var categories: [ExperienceCategory: Int] = [:]
        var feelings: [Feeling: Int] = [:]
        for e in experiences {
            categories[e.category, default: 0] += 1
            if let f = e.feeling { feelings[f, default: 0] += 1 }
        }
        let top = categories.max { a, b in a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue }!.key
        var text = "これまでの\(experiences.count)つの体験では、「\(top.label)」の体験がいちばん多いようです。"
        if let feeling = feelings.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key.rawValue > b.key.rawValue })?.key {
            text += "気持ちは「\(feeling.label)」と書くことが多いですね。"
        }
        if let next = unexplored.first {
            text += "まだの「\(next.label)」の体験も、気が向いたらのぞいてみませんか。"
        } else {
            text += "8つの区画を、ぜんぶ歩いてきました。"
        }
        return text
    }

    /// 文字列から安定した数を作る(ふり返りの問いを選ぶため。実行ごとに変わらない)
    static func stableHash(_ text: String) -> UInt64 {
        var h: UInt64 = 1_469_598_103_934_665_603
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 1_099_511_628_211
        }
        return h
    }
}
