import Foundation
import Observation
import SwiftData
import UIKit
import GoukakuCore
import GoukakuAI

/// 相棒AI(体験を一緒に見つけて、一緒に育つ)の中心。
/// 「いまの自分」と、覚えていること・やってみた体験・手ごたえから文脈を作り、
/// AIRuntime が選んだAI(または体験帳)に頼んで、結果を SwiftData に残す。
/// 義務ではなく体験として誘い、決めるのはいつも本人。点数はつけない。
@MainActor @Observable
final class CompanionModel {
    static let shared = CompanionModel(app: .shared, runtime: .shared)

    let app: AppModel
    let runtime: AIRuntime

    // いまの自分(画面のチップ。前回の選びを覚えておく)
    var budget: TimeBudget = .fifteen { didSet { saveContext() } }
    var place: Place = .home { didSet { saveContext() } }
    var mood: Mood = .normal { didSet { saveContext() } }

    // 提案を作っているあいだの様子
    private(set) var isSuggesting = false
    /// 生成中の提案の名前(書いている途中)
    private(set) var suggestionPreview = ""
    /// 今回出した提案(新しい順に保存もしている)
    private(set) var batch: [ExperienceIdea] = []
    /// いつかの体験を作っているか
    private(set) var isDreaming = false
    private(set) var somedayPreview = ""
    /// コミットの工夫(コミットの id → 工夫)
    private(set) var reframes: [UUID: [ExperienceIdea]] = [:]
    private(set) var reframing: UUID?
    /// ふり返りを作っている記録と、その途中の文
    private(set) var reflecting: UUID?
    private(set) var reflectionPreview = ""
    /// 会話の返事を書いている途中の文
    private(set) var isChatting = false
    private(set) var chatPreview = ""
    /// 本人に伝えること(例:AIの返事が使えなかった)
    var notice: String?
    /// 画面の再計算のきっかけ
    private(set) var revision = 0

    @ObservationIgnored private var suggestTask: Task<Void, Never>?
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    /// そのほかのAIの仕事(ふり返り・いつか・工夫・手紙)。アプリが前から外れるときに止める
    @ObservationIgnored private var aiTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// 保存してある「いまの自分」を読み戻している間は、書き戻さない
    @ObservationIgnored private var restoring = false

    init(app: AppModel, runtime: AIRuntime) {
        self.app = app
        self.runtime = runtime
        loadContext()
        // iOS ではアプリが裏に回ると GPU を使えない(使うと MLX が止まる)ので、前から外れる前に生成を止める
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseAI() }
        })
    }

    /// AIの仕事を始める(前から外れるときに止められるよう、覚えておく)
    private func startAI(_ body: @escaping @MainActor () async -> Void) {
        let id = UUID()
        aiTasks[id] = Task { [weak self] in
            await body()
            self?.aiTasks[id] = nil
        }
    }

    /// 生成中のAIを止める(アプリが前から外れるとき)。止めたものは、体験帳で補うか、もう一度押せば続きを作れる
    func pauseAI() {
        let running = isSuggesting || isChatting || isDreaming || reframing != nil || reflecting != nil || !aiTasks.isEmpty
        guard running else { return }
        suggestTask?.cancel()
        chatTask?.cancel()
        for task in aiTasks.values { task.cancel() }
        if isSuggesting || isDreaming || isChatting {
            notice = "アプリを離れたので、相棒の考えごとを途中で止めました。もう一度押すと続きを考えます"
        }
    }

    var context: ModelContext { app.context }

    private func touch() {
        try? context.save()
        revision &+= 1
    }

    // MARK: いまの自分

    private func loadContext() {
        let parts = app.settings.companionContextRaw.split(separator: "|").map(String.init)
        guard parts.count == 3 else { return }
        restoring = true
        defer { restoring = false }
        if let minutes = Int(parts[0]), let b = TimeBudget(rawValue: minutes) { budget = b }
        if let p = Place(rawValue: parts[1]) { place = p }
        if let m = Mood(rawValue: parts[2]) { mood = m }
    }

    private func saveContext() {
        guard !restoring else { return }
        let raw = "\(budget.rawValue)|\(place.rawValue)|\(mood.rawValue)"
        guard app.settings.companionContextRaw != raw else { return }
        app.settings.companionContextRaw = raw
        try? context.save()
    }

    // MARK: 問い合わせ

    func fetch<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    var notes: [CompanionNote] {
        _ = revision
        return fetch(CompanionNote.self).sorted { $0.createdAt > $1.createdAt }
    }

    var logs: [ExperienceLog] {
        _ = revision
        return fetch(ExperienceLog.self).sorted { $0.at > $1.at }
    }

    var ideas: [ExperienceIdea] {
        _ = revision
        return fetch(ExperienceIdea.self).sorted { $0.createdAt > $1.createdAt }
    }

    /// 「やってみる」に入れた体験
    var planned: [ExperienceIdea] { ideas.filter { $0.status == .planned } }

    /// 「いつか」にとっておいた体験
    var someday: [ExperienceIdea] { ideas.filter { $0.status == .someday } }

    var messages: [CompanionMessage] {
        _ = revision
        return fetch(CompanionMessage.self).sorted { $0.at < $1.at }
    }

    /// 体験の地図とAIの理解
    var growth: GrowthSnapshot {
        let logs = self.logs
        let ideas = self.ideas
        let notes = self.notes
        let firstDates = [logs.last?.at, notes.last?.createdAt, ideas.last?.createdAt, app.settings.companionStartedAt].compactMap { $0 }
        return GrowthSnapshot.make(experienceCategories: logs.filter { $0.source == .experience }.map(\.category),
                                   notes: notes.count, liked: ideas.filter(\.liked).count,
                                   disliked: ideas.filter(\.disliked).count, since: firstDates.min())
    }

    /// AIに渡す文脈(すべて端末の中のデータ)
    func makeContext(now: Date = Date()) -> CompanionContext {
        let ideas = self.ideas
        var affinity: [ExperienceCategory: Int] = [:]
        for idea in ideas {
            if idea.liked { affinity[idea.category, default: 0] += 1 }
            if idea.disliked { affinity[idea.category, default: 0] -= 1 }
            if idea.status == .done { affinity[idea.category, default: 0] += 1 }
        }
        let commits = (app.today.map { $0.required + $0.optional } ?? []).map(\.title)
        return CompanionContext(now: now, budget: budget, place: place, mood: mood,
                                notes: notes.map(\.text),
                                recentExperiences: logs.prefix(6).map(\.title),
                                liked: ideas.filter(\.liked).prefix(4).map(\.title),
                                disliked: ideas.filter(\.disliked).prefix(4).map(\.title),
                                commits: commits, categoryAffinity: affinity)
    }

    /// 最近出したもの(同じ提案をくり返さないため)
    private var recentTitles: [String] {
        Array(ideas.prefix(24).map(\.title))
    }

    private func markStarted() {
        if app.settings.companionStartedAt == nil {
            app.settings.companionStartedAt = Date()
        }
    }

    // MARK: 体験の提案

    func suggest() {
        guard !isSuggesting else { return }
        suggestTask?.cancel()
        isSuggesting = true
        suggestionPreview = ""
        notice = nil
        batch = []
        markStarted()
        // 前回の「出しただけ」の提案はしまう(いいね・ちがうを付けたものは残る)
        for idea in ideas where idea.status == .suggested && idea.kind == .today && idea.feedbackRaw == nil {
            idea.status = .dismissed
        }
        touch()
        suggestTask = Task {
            await runtime.ensureReady()
            let brain = runtime.brain
            let seed = UInt64(Date().timeIntervalSince1970)
            do {
                for try await event in brain.suggestions(context: makeContext(), count: 3, avoid: recentTitles, seed: seed) {
                    switch event {
                    case .progress(let text):
                        suggestionPreview = text
                    case .value(let draft):
                        let idea = ExperienceIdea(draft: draft, engineName: draft.isFromAI ? brain.info.name : "体験帳", kind: .today)
                        context.insert(idea)
                        batch.append(idea)
                        suggestionPreview = ""
                        touch()
                    case .notice(let text):
                        notice = text
                    }
                }
            } catch is CancellationError {
            } catch {
                notice = error.localizedDescription
            }
            await runtime.noteStats()
            isSuggesting = false
            suggestionPreview = ""
        }
    }

    func cancelSuggest() {
        suggestTask?.cancel()
        isSuggesting = false
        suggestionPreview = ""
    }

    /// 「やってみる」に入れる
    func plan(_ idea: ExperienceIdea) {
        idea.status = .planned
        idea.plannedAt = Date()
        touch()
    }

    /// 「いつか」にとっておく
    func keepForSomeday(_ idea: ExperienceIdea) {
        idea.status = .someday
        touch()
    }

    /// いいね/ちがう(もう一度押すと外す)。提案の選び方がこの人に合っていく
    func feedback(_ idea: ExperienceIdea, liked: Bool) {
        let value = liked ? "liked" : "disliked"
        idea.feedbackRaw = idea.feedbackRaw == value ? nil : value
        touch()
    }

    func dismiss(_ idea: ExperienceIdea) {
        idea.status = .dismissed
        batch.removeAll { $0.id == idea.id }
        touch()
    }

    /// 本人が自分で考えた体験を「やってみる」に入れる
    func addOwnIdea(title: String, category: ExperienceCategory) {
        let draft = ExperienceDraft(title: title, line: "", firstStep: "", duration: .fifteen, category: category, origin: .user)
        let idea = ExperienceIdea(draft: draft, engineName: "あなた", kind: .today, status: .planned)
        idea.plannedAt = Date()
        context.insert(idea)
        markStarted()
        touch()
    }

    // MARK: やってみた → ふり返り

    /// やってみた体験を記録し、相棒のふり返りを頼む
    @discardableResult
    func logExperience(idea: ExperienceIdea?, title: String, note: String, feeling: Feeling?,
                       category: ExperienceCategory) -> ExperienceLog {
        let log = ExperienceLog(title: title, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                feeling: feeling, category: category, source: .experience, ideaID: idea?.id)
        context.insert(log)
        if let idea {
            idea.status = .done
            idea.doneAt = Date()
        }
        markStarted()
        app.log("experience", "体験「\(title)」をやってみた")
        touch()
        reflect(log)
        return log
    }

    /// チェックインのあとに、相棒がひとこと返す(コミットの記録とつなぐ)
    func reflectOnCheckIn(habit: HabitSnapshot, achievement: Achievement, note: String) {
        guard app.settings.companionReflectAfterCheckIn else { return }
        let log = ExperienceLog(title: achievement.kind == .minimum ? (habit.minimumTitle ?? habit.title) : habit.title,
                                note: note, feeling: nil, category: .learn, source: .checkIn,
                                achievementID: achievement.id)
        context.insert(log)
        touch()
        reflect(log)
    }

    /// チェックインの記録についた返事
    func checkInLog(for achievementID: UUID) -> ExperienceLog? {
        logs.first { $0.achievementID == achievementID }
    }

    /// チェックインを取り消したら、ついていた返事も消す
    func removeCheckInLog(for achievementID: UUID) {
        for log in logs where log.achievementID == achievementID {
            context.delete(log)
        }
        touch()
    }

    func reflect(_ log: ExperienceLog) {
        let id = log.id
        reflecting = id
        reflectionPreview = ""
        let title = log.title, note = log.note, feeling = log.feeling, category = log.category
        startAI { [self] in
            await runtime.ensureReady()
            let brain = runtime.brain
            do {
                for try await event in brain.reflection(title: title, note: note.isEmpty ? "(書かなかった)" : note,
                                                        feeling: feeling, category: category) {
                    switch event {
                    case .progress(let text):
                        if reflecting == id { reflectionPreview = text }
                    case .value(let draft):
                        guard let target = logs.first(where: { $0.id == id }) else { break }
                        target.reply = draft.reply
                        target.question = draft.question
                        target.replyFromAI = draft.fromAI
                        target.engineName = draft.fromAI ? brain.info.name : "体験帳"
                        if let candidate = draft.noteCandidate,
                           CompanionMemory.isNew(candidate, existing: notes.map(\.text)) {
                            target.noteCandidate = candidate
                        }
                        touch()
                    case .notice(let text):
                        notice = text
                    }
                }
            } catch is CancellationError {
                // 途中で止めた:体験帳の短い返事を残す(返事のない記録にしない)
                if let target = logs.first(where: { $0.id == id }), target.reply == nil {
                    let fallback = ExperienceLibrary.reflection(title: title, note: note, feeling: feeling, category: category)
                    target.reply = fallback.reply
                    target.question = fallback.question
                    target.replyFromAI = false
                    target.engineName = "体験帳"
                    touch()
                }
            } catch {
                notice = error.localizedDescription
            }
            await runtime.noteStats()
            if reflecting == id {
                reflecting = nil
                reflectionPreview = ""
            }
        }
    }

    // MARK: 覚えていること

    /// AIのメモを「覚える」にする
    func acceptNote(from log: ExperienceLog) {
        guard let text = log.noteCandidate else { return }
        remember(text, fromAI: true)
        log.noteCandidate = nil
        touch()
    }

    func declineNote(from log: ExperienceLog) {
        log.noteCandidate = nil
        touch()
    }

    func remember(_ text: String, fromAI: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, CompanionMemory.isNew(trimmed, existing: notes.map(\.text)) else { return }
        context.insert(CompanionNote(text: String(trimmed.prefix(60)), fromAI: fromAI))
        // 多すぎたら、古いAIのメモから消す(本人が書いたものは消さない)
        let aiNotes = notes.filter(\.fromAI)
        if notes.count > CompanionMemory.capacity, let oldest = aiNotes.last {
            context.delete(oldest)
        }
        markStarted()
        touch()
    }

    /// 本人が書いた「わたしについて」を、覚えることに分けて入れる
    func rememberIntroduction(_ text: String) {
        for line in CompanionMemory.split(selfIntroduction: text) {
            remember(line, fromAI: false)
        }
    }

    func forget(_ note: CompanionNote) {
        context.delete(note)
        touch()
    }

    func forgetAll() {
        for note in notes { context.delete(note) }
        touch()
    }

    // MARK: いつかの体験

    func dream(theme: String?) {
        guard !isDreaming else { return }
        isDreaming = true
        somedayPreview = ""
        notice = nil
        markStarted()
        startAI { [self] in
            await runtime.ensureReady()
            let brain = runtime.brain
            do {
                for try await event in brain.someday(context: makeContext(), theme: theme, count: 3, avoid: recentTitles,
                                                     seed: UInt64(Date().timeIntervalSince1970)) {
                    switch event {
                    case .progress(let text): somedayPreview = text
                    case .value(let draft):
                        let idea = ExperienceIdea(draft: draft, engineName: draft.isFromAI ? brain.info.name : "体験帳",
                                                  kind: .someday, status: .suggested)
                        context.insert(idea)
                        somedayPreview = ""
                        touch()
                    case .notice(let text): notice = text
                    }
                }
            } catch is CancellationError {
            } catch {
                notice = error.localizedDescription
            }
            isDreaming = false
            somedayPreview = ""
        }
    }

    /// いつかの体験の「最初の一歩」を、今日の「やってみる」に入れる
    func planFirstStep(of idea: ExperienceIdea) {
        let step = idea.firstStep.isEmpty ? idea.title : idea.firstStep
        // もとの体験と同じ出どころにする(相棒・体験帳+相棒・体験帳・自分で)
        let origin: ExperienceDraft.Origin
        switch idea.originRaw {
        case "ai": origin = .ai(idea.engineName)
        case "tailored": origin = .tailored(idea.engineName, "")
        case "library": origin = .library("")
        default: origin = .user
        }
        let draft = ExperienceDraft(title: String(step.prefix(30)), line: "「\(idea.title)」への一歩", firstStep: "",
                                    duration: .fifteen, category: idea.category, origin: origin)
        let planned = ExperienceIdea(draft: draft, engineName: idea.engineName, kind: .today, status: .planned)
        planned.plannedAt = Date()
        context.insert(planned)
        notice = "最初の一歩を「やってみる」に入れました(体験タブ)"
        touch()
    }

    /// 生まれたばかりの「いつか」の候補(まだとっておいていないもの)
    var somedayCandidates: [ExperienceIdea] {
        ideas.filter { $0.kind == .someday && $0.status == .suggested }
    }

    // MARK: コミットを体験にする工夫

    func reframe(_ habit: HabitSnapshot) {
        guard reframing == nil else { return }
        reframing = habit.id
        notice = nil
        let avoid = (reframes[habit.id] ?? []).map(\.title) + recentTitles
        startAI { [self] in
            await runtime.ensureReady()
            let brain = runtime.brain
            var made: [ExperienceIdea] = []
            do {
                for try await event in brain.reframes(commit: habit.title, context: makeContext(), count: 2, avoid: avoid) {
                    if case .value(let draft) = event {
                        let idea = ExperienceIdea(draft: draft, engineName: draft.isFromAI ? brain.info.name : "体験帳",
                                                  kind: .reframe, commitTitle: habit.title)
                        context.insert(idea)
                        made.append(idea)
                        reframes[habit.id] = made
                        touch()
                    } else if case .notice(let text) = event {
                        notice = text
                    }
                }
            } catch is CancellationError {
            } catch {
                notice = error.localizedDescription
            }
            reframing = nil
        }
    }

    // MARK: 相棒と話す

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isChatting else { return }
        let history = messages.map { ChatTurn($0.role, $0.text) }
        context.insert(CompanionMessage(role: .user, text: message, engineName: nil))
        markStarted()
        touch()
        isChatting = true
        chatPreview = ""
        chatTask = Task {
            await runtime.ensureReady()
            let brain = runtime.brain
            do {
                for try await event in brain.chat(context: makeContext(), history: history, message: message) {
                    switch event {
                    case .progress(let text): chatPreview = text
                    case .value(let reply):
                        context.insert(CompanionMessage(role: .assistant, text: reply, engineName: brain.info.name))
                        touch()
                    case .notice(let text): notice = text
                    }
                }
            } catch is CancellationError {
            } catch {
                notice = error.localizedDescription
            }
            await runtime.noteStats()
            isChatting = false
            chatPreview = ""
        }
    }

    func stopChat() {
        chatTask?.cancel()
        isChatting = false
        chatPreview = ""
    }

    func clearChat() {
        for m in messages { context.delete(m) }
        touch()
    }

    // MARK: 週の手紙

    /// その週の体験から、相棒の手紙を書く(届くたびに onUpdate を呼ぶ)
    func weeklyLetter(week: CycleID, onUpdate: @escaping @MainActor (String, Bool) -> Void) {
        let cal = app.cycleCalendar
        let start = cal.start(of: week)
        let end = cal.start(of: cal.cycle(week, offsetBy: 7))
        let weekLogs = logs.filter { $0.at >= start && $0.at < end && $0.source == .experience }
        let days = app.weekOutcomes(week)
        let achieved = days.filter { [.achieved, .minimum].contains($0.outcome) }.count
        let planned = days.filter { [.achieved, .minimum, .missed].contains($0.outcome) }.count
        let experiences = weekLogs.map { (title: $0.title, category: $0.category) }
        let notes = self.notes.map(\.text)
        startAI { [self] in
            await runtime.ensureReady()
            let brain = runtime.brain
            do {
                for try await event in brain.letter(experiences: experiences, achievedDays: achieved, plannedDays: planned,
                                                    notes: notes, context: makeContext(), seed: UInt64(week.day)) {
                    switch event {
                    case .progress(let text): onUpdate(text, false)
                    case .value(let text): onUpdate(text, true)
                    case .notice: break
                    }
                }
            } catch is CancellationError {
                // 途中で止めた:体験帳で書いた手紙にする
                onUpdate(ExperienceLibrary.letter(experiences: experiences, achievedDays: achieved,
                                                  context: makeContext(), seed: UInt64(week.day)), true)
            } catch {
                onUpdate(error.localizedDescription, true)
            }
        }
    }

    // MARK: 全部消す(設定の全削除から)

    /// 画面のために持っている体験を手放す(データの削除の前に呼ぶ)
    func resetInMemoryState() {
        suggestTask?.cancel()
        chatTask?.cancel()
        for task in aiTasks.values { task.cancel() }
        aiTasks = [:]
        batch = []
        reframes = [:]
        isSuggesting = false
        isChatting = false
        reflecting = nil
        notice = nil
        revision &+= 1
    }
}
