import Foundation

/// 相棒の頭の中から届く知らせ
public enum BrainEvent<Value: Sendable>: Sendable {
    /// 生成中の文章(掃除ずみ。表示用)
    case progress(String)
    /// できあがった1つ
    case value(Value)
    /// 本人に伝えること(例:AIの返事が使えなかったので体験帳から出した)
    case notice(String)
}

/// 相棒の「頭」。AI(LanguageEngine)があれば AI で、なければ体験帳で答える。
/// AIの出力が形を守らない・安全でないときは1回だけ作り直し、それでもだめなら体験帳で補う。
/// どの端末・どの状態でも、ちゃんと答えが返ることを大事にしている(完全環境適応)。
public struct CompanionBrain: Sendable {
    public let engine: (any LanguageEngine)?
    public let tuning: GenerationTuning

    public init(engine: (any LanguageEngine)?, tuning: GenerationTuning = GenerationTuning()) {
        self.engine = engine
        self.tuning = tuning
    }

    public var info: EngineInfo { engine?.info ?? .rules }
    public var usesAI: Bool { engine != nil }

    // MARK: 体験の提案

    /// 今の様子に合う体験を count 個(1つずつ届く)
    public func suggestions(context: CompanionContext, count: Int = 3, avoid: [String],
                            seed: UInt64) -> AsyncThrowingStream<BrainEvent<ExperienceDraft>, Error> {
        let angles = AnglePlanner.angles(for: context, count: count, seed: seed)
        return run { emit in
            var produced: [String] = []
            var fellBack = false
            for (index, angle) in angles.enumerated() {
                var draft: ExperienceDraft?
                let pickSeed = seed &+ UInt64(produced.count)
                if let engine, !fellBack {
                    do {
                        if self.tuning.freeSuggestions {
                            // AIが自由に考える(大きいモデル)
                            let hint = IdeaHints.pick(angle, seed: seed &+ UInt64(index) &* 7919)
                            draft = try await self.generateDraft(engine: engine, attempts: 2, emit: emit) { attempt in
                                PromptBook.suggestion(context: context, angle: angle, avoid: avoid + produced,
                                                      tuning: self.tuning,
                                                      temperature: attempt == 0 ? self.tuning.suggestionTemperature : 0.6,
                                                      hint: attempt == 0 && self.tuning.useHints ? hint : nil)
                            } parse: { raw in
                                ExperienceParser.suggestion(from: raw, angle: angle, budget: context.budget, engine: engine.info.name)
                            } accept: { d in
                                !Self.isDuplicate(d.title, of: avoid + produced) && ContextFit.fits(d, context: context)
                            }
                        } else if let base = Self.libraryPick(context: context, angle: angle, avoid: avoid, produced: produced,
                                                              seed: pickSeed) {
                            // 体験帳の確かな体験に、AIがこの人向けのひとことを添える(小さいモデル)
                            draft = try await self.tailored(base, engine: engine, context: context, purpose: nil, emit: emit)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        fellBack = true
                        emit(.notice("AIが使えなかったので、体験帳から選びました(\(error.localizedDescription))"))
                    }
                }
                if draft == nil {
                    draft = Self.libraryPick(context: context, angle: angle, avoid: avoid, produced: produced, seed: pickSeed)
                }
                if let draft {
                    produced.append(draft.title)
                    emit(.value(draft))
                }
            }
        }
    }

    /// 続けていること(コミット)を、ちょっと楽しみな体験に変える工夫
    public func reframes(commit: String, context: CompanionContext, count: Int = 2,
                         avoid: [String]) -> AsyncThrowingStream<BrainEvent<ExperienceDraft>, Error> {
        run { emit in
            var produced: [String] = []
            var fellBack = false
            let library = ExperienceLibrary.reframes(for: commit, count: count + 3, avoid: Set(avoid))
            for index in 0..<count {
                var draft: ExperienceDraft?
                let base = library.first { !produced.contains($0.title) } ?? library.dropFirst(index).first
                if let engine, !fellBack {
                    do {
                        if self.tuning.freeSuggestions {
                            draft = try await self.generateDraft(engine: engine, attempts: 2, emit: emit) { _ in
                                PromptBook.reframe(commit: commit, context: context, avoid: avoid + produced, tuning: self.tuning)
                            } parse: { raw in
                                ExperienceParser.suggestion(from: raw, angle: .learn, budget: context.budget, engine: engine.info.name)
                            } accept: { d in
                                !Self.isDuplicate(d.title, of: avoid + produced) && ContextFit.fits(d, context: context)
                            }
                        } else if let base {
                            draft = try await self.tailored(base, engine: engine, context: context,
                                                            purpose: "これは、この人が続けている「\(commit)」を、ちょっと楽しみにする工夫です。",
                                                            emit: emit)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        fellBack = true
                        emit(.notice("AIが使えなかったので、体験帳から選びました(\(error.localizedDescription))"))
                    }
                }
                if draft == nil {
                    draft = base
                }
                if let draft {
                    produced.append(draft.title)
                    emit(.value(draft))
                }
            }
        }
    }

    /// 人生のどこかで味わってみたい「いつかの体験」
    public func someday(context: CompanionContext, theme: String?, count: Int = 3, avoid: [String],
                        seed: UInt64) -> AsyncThrowingStream<BrainEvent<ExperienceDraft>, Error> {
        let planned = AnglePlanner.angles(for: CompanionContext(now: context.now, timeZone: context.timeZone,
                                                                budget: .hourPlus, place: .anywhere, mood: .energetic,
                                                                categoryAffinity: context.categoryAffinity),
                                          count: count, seed: seed)
        let angles = planned.isEmpty ? [ExperienceCategory.first] : planned
        return run { emit in
            var produced: [String] = []
            var fellBack = false
            for angle in angles {
                var draft: ExperienceDraft?
                let base = ExperienceLibrary.someday(for: context, angle: angle, avoid: Set(avoid + produced),
                                                     seed: seed &+ UInt64(produced.count))
                if let engine, !fellBack {
                    do {
                        if self.tuning.freeSuggestions {
                            draft = try await self.generateDraft(engine: engine, attempts: 2, emit: emit) { _ in
                                PromptBook.someday(context: context, angle: angle, theme: theme, avoid: avoid + produced,
                                                   tuning: self.tuning)
                            } parse: { raw in
                                ExperienceParser.someday(from: raw, angle: angle, engine: engine.info.name)
                            } accept: { d in
                                !Self.isDuplicate(d.title, of: avoid + produced)
                            }
                        } else if let base {
                            var purpose = "これは、人生のどこかで味わってみたい「いつかの体験」です。"
                            if let theme, !theme.trimmingCharacters(in: .whitespaces).isEmpty {
                                purpose += "この人がいま気になっていること: \(theme)"
                            }
                            draft = try await self.tailored(base, engine: engine, context: context, purpose: purpose, emit: emit)
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        fellBack = true
                        emit(.notice("AIが使えなかったので、体験帳から選びました(\(error.localizedDescription))"))
                    }
                }
                if draft == nil {
                    draft = base
                }
                if let draft {
                    produced.append(draft.title)
                    emit(.value(draft))
                }
            }
        }
    }

    // MARK: ふり返り

    public func reflection(title: String, note: String, feeling: Feeling?,
                           category: ExperienceCategory?) -> AsyncThrowingStream<BrainEvent<ReflectionDraft>, Error> {
        run { emit in
            if let engine {
                do {
                    for attempt in 0..<2 {
                        var request = PromptBook.reflection(title: title, note: note, feeling: feeling, tuning: self.tuning)
                        if attempt > 0 { request.temperature = 0.5 }
                        var raw = ""
                        for try await piece in engine.generate(request) {
                            raw += piece
                            emit(.progress(Self.replyPreview(raw)))
                        }
                        if let draft = ExperienceParser.reflection(from: raw, title: title, note: note) {
                            emit(.value(draft))
                            return
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    emit(.notice("AIが使えなかったので、短い返事にしました(\(error.localizedDescription))"))
                }
            }
            emit(.value(ExperienceLibrary.reflection(title: title, note: note, feeling: feeling, category: category)))
        }
    }

    // MARK: 週の手紙

    public func letter(experiences: [(title: String, category: ExperienceCategory)], achievedDays: Int,
                       plannedDays: Int, notes: [String], context: CompanionContext,
                       seed: UInt64) -> AsyncThrowingStream<BrainEvent<String>, Error> {
        run { emit in
            if let engine {
                do {
                    let request = PromptBook.letter(experiences: experiences.map(\.title), achievedDays: achievedDays,
                                                    plannedDays: plannedDays, notes: notes, tuning: self.tuning)
                    var raw = ""
                    for try await piece in engine.generate(request) {
                        raw += piece
                        emit(.progress(OutputCleaner.clean(raw)))
                    }
                    if let text = ExperienceParser.prose(from: raw, limit: 420), ContentGuard.isAcceptable(text: text) {
                        emit(.value(text))
                        return
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    emit(.notice("AIが使えなかったので、体験帳から書きました(\(error.localizedDescription))"))
                }
            }
            emit(.value(ExperienceLibrary.letter(experiences: experiences, achievedDays: achievedDays,
                                                 context: context, seed: seed)))
        }
    }

    // MARK: 相棒の気づき

    /// やってみた体験の記録から、相棒が気づいたこと(AIがなければ体験帳のルールで)
    public func insight(experiences: [ExperienceMemo], notes: [String],
                        unexplored: [ExperienceCategory]) -> AsyncThrowingStream<BrainEvent<InsightDraft>, Error> {
        run { emit in
            if let engine, !experiences.isEmpty {
                do {
                    let request = PromptBook.insight(experiences: experiences, notes: notes, unexplored: unexplored,
                                                     tuning: self.tuning)
                    var raw = ""
                    for try await piece in engine.generate(request) {
                        raw += piece
                        emit(.progress(OutputCleaner.clean(raw)))
                    }
                    if let text = ExperienceParser.prose(from: raw, limit: 300), ContentGuard.isAcceptable(text: text),
                       TextCheck.hasJapanese(text) {
                        emit(.value(InsightDraft(text: text, fromAI: true)))
                        return
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    emit(.notice("AIが使えなかったので、記録から書きました(\(error.localizedDescription))"))
                }
            }
            emit(.value(InsightDraft(text: ExperienceLibrary.insight(experiences: experiences, unexplored: unexplored),
                                     fromAI: false)))
        }
    }

    // MARK: 相棒と話す

    /// 会話はAIがあるときだけ(体験帳では話せない)
    public func chat(context: CompanionContext, history: [ChatTurn],
                     message: String) -> AsyncThrowingStream<BrainEvent<String>, Error> {
        run { emit in
            guard let engine else {
                throw AIError.unavailable("会話にはAIのモデルが要ります。設定 › AI から入れられます")
            }
            let request = PromptBook.chat(context: context, history: history, message: message, tuning: self.tuning)
            var raw = ""
            for try await piece in engine.generate(request) {
                raw += piece
                emit(.progress(OutputCleaner.clean(raw)))
            }
            guard let text = ExperienceParser.prose(from: raw, limit: 900) else { throw AIError.emptyOutput }
            emit(.value(text))
        }
    }

    // MARK: 中身

    /// 1つ作る:生成 → 読む → だめなら作り直す
    func generateDraft(engine: any LanguageEngine, attempts: Int,
                       emit: @Sendable (BrainEvent<ExperienceDraft>) -> Void,
                       request: (Int) -> GenerationRequest,
                       parse: (String) -> ExperienceDraft?,
                       accept: (ExperienceDraft) -> Bool) async throws -> ExperienceDraft? {
        for attempt in 0..<attempts {
            var raw = ""
            for try await piece in engine.generate(request(attempt)) {
                raw += piece
                emit(.progress(Self.titlePreview(raw)))
            }
            if let draft = parse(raw), accept(draft) { return draft }
        }
        return nil
    }

    /// 体験帳の体験に、AIがこの人向けのひとことを添える(だめなら体験帳のまま返す)
    func tailored(_ base: ExperienceDraft, engine: any LanguageEngine, context: CompanionContext, purpose: String?,
                  emit: @Sendable (BrainEvent<ExperienceDraft>) -> Void) async throws -> ExperienceDraft {
        emit(.progress(base.title))
        for attempt in 0..<2 {
            var request = PromptBook.tailor(base, context: context, purpose: purpose, tuning: tuning)
            if attempt > 0 { request.temperature = 0.5 }
            var raw = ""
            for try await piece in engine.generate(request) { raw += piece }
            if let line = ExperienceParser.tailoredLine(from: raw, title: base.title, context: context) {
                var draft = base
                draft.line = line
                if case .library(let id) = base.origin {
                    draft.origin = .tailored(engine.info.name, id)
                } else {
                    draft.origin = .tailored(engine.info.name, "")
                }
                return draft
            }
        }
        return base
    }

    /// 体験帳から、その種類の体験を1つ(なければ種類を問わず)。
    /// 最近出したものを避けると何も残らないときは、今回まだ出していないものから選ぶ(提案が欠けないように)
    static func libraryPick(context: CompanionContext, angle: ExperienceCategory, avoid: [String], produced: [String],
                            seed: UInt64) -> ExperienceDraft? {
        for excluded in [Set(avoid + produced), Set(produced)] {
            if let found = ExperienceLibrary.pick(for: context, count: 1, avoid: excluded, seed: seed, angles: [angle]).first
                ?? ExperienceLibrary.pick(for: context, count: 1, avoid: excluded, seed: seed &+ 99).first {
                return found
            }
        }
        return nil
    }

    /// 似た体験か(同じ名前・頭の6文字が同じ)
    static func isDuplicate(_ title: String, of others: [String]) -> Bool {
        let key = normalize(title)
        return others.contains { other in
            let o = normalize(other)
            return o == key || (key.count >= 6 && o.count >= 6 && o.prefix(6) == key.prefix(6))
        }
    }

    static func normalize(_ text: String) -> String {
        text.filter { !$0.isWhitespace && !"「」『』、。・".contains($0) }
    }

    /// 生成中の提案から、表示する名前を取る
    static func titlePreview(_ raw: String) -> String {
        let text = OutputCleaner.clean(raw)
        for line in text.components(separatedBy: .newlines) {
            if let (key, value) = FieldReader.split(line, keys: ["体験"]), key == "体験" { return value }
        }
        return ""
    }

    /// 生成中のふり返りから、返事の部分を取る
    static func replyPreview(_ raw: String) -> String {
        let text = OutputCleaner.clean(raw)
        for line in text.components(separatedBy: .newlines) {
            if let (key, value) = FieldReader.split(line, keys: ["返事"]), key == "返事" { return value }
        }
        return text.components(separatedBy: .newlines).first.map(OutputCleaner.stripDecoration) ?? ""
    }

    /// 非同期の処理を、知らせの流れにする(キャンセルすると中の処理も止まる)
    private func run<Value: Sendable>(
        _ body: @escaping @Sendable (_ emit: @Sendable (BrainEvent<Value>) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<BrainEvent<Value>, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await body { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
