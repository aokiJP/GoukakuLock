import SwiftUI
import UIKit
import GoukakuAI

/// 相棒と話す。どんな体験をしてみたいか、話しながら考える(会話はこの iPhone の中だけ)
struct CompanionChatView: View {
    @Environment(CompanionModel.self) private var companion
    @Environment(AIRuntime.self) private var runtime
    @State private var draft = ""
    @State private var confirmClear = false
    @FocusState private var focused: Bool

    private let starters = [
        "最近、ちょっと退屈かもしれない",
        "この週末、何をしてみよう",
        "人生でいつかやってみたいことを一緒に考えて",
        "勉強を、もう少し楽しくするには?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !runtime.usesAI {
                            noAI
                        } else if companion.messages.isEmpty {
                            intro
                        }
                        ForEach(companion.messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                        if companion.isChatting {
                            PencilNote(text: companion.chatPreview, caption: "相棒", writing: true)
                                .id("writing")
                        }
                    }
                    .padding()
                }
                .onChange(of: companion.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(companion.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: companion.chatPreview) { _, _ in
                    proxy.scrollTo("writing", anchor: .bottom)
                }
            }
            if runtime.usesAI {
                inputBar
            }
        }
        .background(Theme.paper)
        .navigationTitle("相棒と話す")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("会話をすべて消す", role: .destructive) { confirmClear = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(companion.messages.isEmpty)
            }
        }
        .confirmationDialog("会話をすべて消しますか?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("消す", role: .destructive) { companion.clearChat() }
        }
        .onDisappear { if companion.isChatting { companion.stopChat() } }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            PencilNote(text: "こんにちは。どんな体験をしてみたいか、なんでも話してください。決めるのはあなたで、わたしは一緒に考えるだけです。",
                       caption: "相棒(\(runtime.engineInfo.name))")
            Text("話しはじめの例")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            ForEach(starters, id: \.self) { starter in
                Button {
                    companion.send(starter)
                } label: {
                    Text(starter)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.paperSunken))
                        .overlay(Capsule().strokeBorder(Theme.rule))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
            }
        }
    }

    private var noAI: some View {
        VStack(alignment: .leading, spacing: 10) {
            PencilNote(text: "いまは体験帳(AIなし)で動いているので、会話はできません。AIのモデルを入れるか、Apple Intelligence をオンにすると話せます。",
                       caption: "相棒")
            NavigationLink("AI の設定を開く") { AISettingsView() }
                .font(.subheadline.weight(.semibold))
                .tint(Theme.pencil)
        }
    }

    @ViewBuilder
    private func bubble(_ message: CompanionMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.rule))
                    .contextMenu {
                        Button {
                            companion.remember(message.text, fromAI: false)
                        } label: {
                            Label("相棒に覚えてもらう", systemImage: "bookmark")
                        }
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("コピー", systemImage: "doc.on.doc")
                        }
                    }
            }
        } else {
            PencilNote(text: message.text, caption: "相棒")
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("相棒に話す", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.paperSunken, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rule))
            if companion.isChatting {
                Button {
                    companion.stopChat()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .tint(Theme.muted)
                .accessibilityLabel("止める")
            } else {
                Button {
                    companion.send(draft)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .tint(Theme.seal)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("送る")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
