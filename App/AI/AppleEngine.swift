import Foundation
import GoukakuAI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence(Foundation Models のシステムモデル)で文章を作るAI。
/// iOS 26 以降・Apple Intelligence がオンの iPhone で使える。モデルのダウンロードは要らない。
/// 手本の1往復は指示文に、会話の履歴は頼みの文に書き込んで渡す(どのAIでも同じプロンプトを使うため)。
/// アプリの側では話す中身をしばらない。Apple のガードレールも、いちばんゆるい設定で使う
struct AppleEngine: LanguageEngine {
    let info = EngineInfo(kind: .apple, id: "apple", name: "Apple Intelligence")

    static var isAvailable: Bool { DeviceProbe.appleIntelligence() == .available }

    func generate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
                        let session = LanguageModelSession(model: model, instructions: Self.instructions(for: request))
                        let options = GenerationOptions(sampling: nil, temperature: request.temperature,
                                                        maximumResponseTokens: request.maxTokens)
                        var sent = ""
                        for try await snapshot in session.streamResponse(to: Self.prompt(for: request), options: options) {
                            try Task.checkCancellation()
                            let text = snapshot.content
                            if text.hasPrefix(sent) {
                                let added = String(text.dropFirst(sent.count))
                                if !added.isEmpty { continuation.yield(added) }
                            } else {
                                // 途中で書き直された(まれ)。差分が取れないので、ここまでを区切って送り直す
                                continuation.yield("\n" + text)
                            }
                            sent = text
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch {
                        continuation.finish(throwing: AIError.generationFailed(error.localizedDescription))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable("Apple Intelligence は iOS 26 以降で使えます")) }
    }

    /// 役割の説明と、答え方の手本(あれば)
    static func instructions(for request: GenerationRequest) -> String {
        var text = request.system
        let pairs = stride(from: 0, to: request.examples.count - 1, by: 2).compactMap { i -> (String, String)? in
            let a = request.examples[i], b = request.examples[i + 1]
            guard a.role == .user, b.role == .assistant else { return nil }
            return (a.text, b.text)
        }
        for (user, assistant) in pairs {
            text += "\n\n次は、頼まれ方と答え方の例です。\n【例の頼み】\n\(user)\n【例の答え】\n\(assistant)"
        }
        return text
    }

    /// 頼みの文(会話の履歴があれば、その流れを添える)
    static func prompt(for request: GenerationRequest) -> String {
        guard !request.history.isEmpty else { return request.prompt }
        let lines = request.history.map { ($0.role == .user ? "あなた: " : "相棒: ") + $0.text }
        return "これまでの会話:\n" + lines.joined(separator: "\n") + "\n\nいまのメッセージ:\n" + request.prompt
    }
}
