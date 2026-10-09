import SwiftUI
import UIKit
import GoukakuCore

/// 写真で記録(仕様書 第6.2節):アプリ内のカメラで撮ったものだけ。ライブラリからは選べない(過去の写真を使い回せない)。
/// 撮影時刻を残し、位置情報などのメタデータは保存しない。
struct PhotoCheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let habit: HabitSnapshot
    @State private var image: UIImage?
    @State private var showingCamera = false
    @State private var note = ""
    @State private var useMinimum = false
    @State private var recorded: Achievement?
    @State private var drawn: CGFloat = 0

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Group {
            if let recorded {
                done(recorded)
            } else {
                form
            }
        }
        .navigationTitle("写真で記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $image)
                .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: recorded?.id)
    }

    private var form: some View {
        Form {
            Section {
                Text(habit.title)
                    .font(Theme.heading(.title3))
                    .foregroundStyle(Theme.ink)
            }
            Section {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button {
                    showingCamera = true
                } label: {
                    Label(image == nil ? "カメラで撮る" : "撮り直す", systemImage: "camera")
                }
                .disabled(!cameraAvailable)
                if !cameraAvailable {
                    Text("この端末ではカメラが使えません。")
                        .font(.footnote)
                        .foregroundStyle(Theme.seal)
                }
            } footer: {
                Text("アプリ内のカメラで撮った写真だけが使えます(ライブラリからは選べません)。位置情報は保存しません。写真は90日で消えます。")
            }
            Section("ひとこと(任意)") {
                TextField("例:腕立て30回、終わり", text: $note, axis: .vertical)
            }
            if habit.minimumTitle != nil {
                Section {
                    Toggle("最小版で記録する", isOn: $useMinimum)
                        .disabled(!model.canUseMinimum())
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(useMinimum ? "最小版で記録する" : "記録する") { save() }
                .buttonStyle(SealButtonStyle())
                .disabled(image == nil)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
        }
    }

    private func save() {
        guard let image else { return }
        let fileName: String
        do {
            fileName = try EvidenceStore.save(image)
        } catch {
            model.show("写真を保存できませんでした", error.localizedDescription)
            return
        }
        if let achievement = model.checkIn(habit: habit, minimum: useMinimum,
                                           evidence: .photo(fileName: fileName, note: note)) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { recorded = achievement }
        }
    }

    private func done(_ achievement: Achievement) -> some View {
        VStack(spacing: 16) {
            Spacer()
            HanamaruView(progress: drawn)
                .frame(width: 180, height: 180)
                .onAppear { withAnimation(.easeInOut(duration: 1.2)) { drawn = 1 } }
            Text("記録しました")
                .font(Theme.heading())
                .foregroundStyle(Theme.ink)
            if let minutes = achievement.grantsMinutes {
                Text("\(Fmt.duration(minutes: minutes))、お金を使うアプリのロックが外れます。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            } else if model.decision?.todaySatisfied == true {
                Text("今日の必須コミットをすべて達成。ロックが外れました。")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("閉じる") { dismiss() }
                .buttonStyle(SealButtonStyle())
                .padding()
        }
    }
}

/// アプリ内のカメラ(撮るだけ。ライブラリは開かない)
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
