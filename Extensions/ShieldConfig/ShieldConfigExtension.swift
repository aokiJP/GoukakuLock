import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit
import GoukakuCore
import GoukakuKit

/// シールド(ロック中の対象アプリを開いたときにシステムが出す画面)の文言
final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let text: ShieldText
        if let store = AppGroup.store, let state = try? store.load() {
            text = ShieldCopy.make(state: state, extra: store.pendingAchievements(), now: Date())
        } else {
            text = ShieldText(title: "今日のコミットがまだです",
                              subtitle: "本体アプリを開いてチェックインしてください。",
                              primaryButton: "チェックインする", secondaryButton: "閉じる")
        }
        // 朱(本体アプリの合格印と同じ色)
        let seal = UIColor(red: 0xC9 / 255, green: 0x3A / 255, blue: 0x2B / 255, alpha: 1)
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            icon: UIImage(systemName: "lock.fill")?.withTintColor(seal, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: text.title, color: .label),
            subtitle: ShieldConfiguration.Label(text: text.subtitle, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: text.primaryButton, color: .white),
            primaryButtonBackgroundColor: seal,
            secondaryButtonLabel: ShieldConfiguration.Label(text: text.secondaryButton, color: .secondaryLabel))
    }
}
