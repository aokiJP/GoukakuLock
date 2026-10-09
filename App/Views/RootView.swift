import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(NotificationRouter.self) private var router

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .sheet(isPresented: Binding(
            get: { router.openCheckIn && !model.needsOnboarding },
            set: { router.openCheckIn = $0 }
        )) {
            CheckInPickerView()
        }
        .overlay {
            if let celebration = model.celebration {
                CelebrationView(celebration: celebration)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.celebration?.id)
        .onOpenURL { url in
            router.handle(url: url)
        }
        .alert(model.message?.title ?? "",
               isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }),
               presenting: model.message) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message.body)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("今日", systemImage: "checkmark.seal") {
                HomeView()
            }
            Tab("記録", systemImage: "calendar") {
                HistoryView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }
}
