import Foundation
import SwiftUI
import UIKit

struct Profile: Codable {
    var situation = "室内・ひとり"
    var interests = "発見、創作"
    var mood = "気軽に"
    var minutes = 3
    var tools = "iPhoneだけ"
    var likes: [String: Int] = [:]
}
struct Archive: Codable {
    var version = 1
    var profile = Profile()
    var current: Session?
    var saved: [Session] = []
    var history: [Session] = []
}
@MainActor final class Store: ObservableObject {
    @Published var data = Archive()
    @Published var generating = false
    @Published var error: String?
    @Published var paused = false
    @Published var sheetOpen = false
    private let ai = LocalAI()
    private var task: Task<Void, Never>?
    private var generationID = UUID()
    private let file: URL
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Asobi/state.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let bytes = try Data(contentsOf: file)
                guard bytes.count < 5_000_000 else { throw PlayError.invalid("保存データが大きすぎます") }
                let archive = try JSONDecoder().decode(Archive.self, from: bytes)
                guard archive.version == 1, archive.saved.count <= 30, archive.history.count <= 20 else { throw PlayError.invalid("保存形式が不正です") }
                try archive.current?.validateSaved()
                for session in archive.saved + archive.history { try session.validateSaved() }
                data = archive
            } catch { self.error = "保存データを読み込めませんでした：\(error.localizedDescription)" }
        }
    }
    func persist() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "保存できませんでした：\(error.localizedDescription)" }
    }
    func generate(_ intent: String = "新しい体験") {
        let previousTask = task
        cancel()
        error = nil
        let id = UUID(); generationID = id
        generating = true
        let profile = data.profile
        let snapshot = data.current
        let memory = snapshot.map { s in
            "Title: \(s.experience.title)\nCurrent: \(s.node.text)\nScores: \(s.values)\nRecent choices: " + s.moves.suffix(6).map { "\($0.action): \(String($0.note.prefix(100)))" }.joined(separator: "; ")
        } ?? ""
        let recent = data.history.suffix(4).map { $0.experience.title }.joined(separator: ",")
        let userData: [String: String] = ["intent": intent, "situation": String(profile.situation.prefix(120)), "interests": String(profile.interests.prefix(120)), "mood": String(profile.mood.prefix(60)), "minutes": String(profile.minutes), "tools": String(profile.tools.prefix(120)), "preferences": String(describing: profile.likes), "recent": recent, "previous": memory]
        let context = String(data: (try? JSONEncoder().encode(userData)) ?? Data(), encoding: .utf8) ?? ""
        task = Task {
            do {
                await previousTask?.value
                try Task.checkCancellation()
                let experience = try await ai.generate(context: context)
                try Task.checkCancellation()
                guard generationID == id else { return }
                if let old = data.current {
                    data.history.append(old)
                    data.history = Array(data.history.suffix(20))
                }
                data.current = try Session(experience)
                persist()
            } catch is CancellationError { }
            catch { if generationID == id { self.error = error.localizedDescription } }
            if generationID == id { generating = false; task = nil }
        }
    }
    func cancel() {
        task?.cancel()
        generationID = UUID(); generating = false
    }
    func act(_ action: Action, note: String) {
        guard !generating && !paused else { return }
        do {
            try data.current?.apply(action.id, note: note, randomIndex: Int.random(in: 0..<(action.random?.count ?? 1)))
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func tick() {
        guard !paused && !sheetOpen && !generating && data.current?.finished == false else { return }
        let previous = data.current?.nodeID
        data.current?.tick()
        if previous != data.current?.nodeID { persist() }
    }
    func save() {
        guard let current = data.current else { return }
        data.saved.removeAll { $0.id == current.id }
        data.saved.insert(current, at: 0)
        data.saved = Array(data.saved.prefix(30)); persist()
    }
    func resume(_ session: Session) {
        cancel(); data.current = session; persist()
    }
    func react(_ liked: Bool) {
        for tag in data.current?.experience.tags ?? [] {
            data.profile.likes[tag] = max(-20, min(20, data.profile.likes[tag, default: 0] + (liked ? 1 : -1)))
        }
        if data.profile.likes.count > 60 {
            data.profile.likes = Dictionary(uniqueKeysWithValues: data.profile.likes.sorted { abs($0.value) > abs($1.value) }.prefix(60).map { ($0.key, $0.value) })
        }
        persist()
        generate(liked ? "気に入った。直前の行動と発見から新しい続編を発明" : "違う気分。ジャンルと仕組みを大胆に変更")
    }
    func background() {
        paused = true; cancel(); persist()
        Task { await ai.unload() }
    }
    func memoryWarning() { cancel(); Task { await ai.unload() } }
}
