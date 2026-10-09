import Foundation
import Darwin
import Security
import BackgroundTasks
import GoukakuCore

/// アプリ全体の定数(どの実行コンテキストからも読めるよう、アクターに属さない場所に置く)
enum AppConstants {
    /// バックグラウンド更新の ID(Info.plist の BGTaskSchedulerPermittedIdentifiers と同じ)
    static let refreshTaskID = "com.aokijp.goukakulock.refresh"
    /// 「やめる合図」の一文(設定画面と一時停止の画面に置く)
    static let quitSignal = "この仕組みが習慣の補助輪ではなく檻に感じ始めたら、それがやめる合図です。"
}

/// 次のバックグラウンド更新を予約する(いつ実行されるかはシステム次第。保険の一つ)
func scheduleNextRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: AppConstants.refreshTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
    try? BGTaskScheduler.shared.submit(request)
}

/// 時計の基準(改ざん検知)。壁時計・単調時計(スリープ中も進む)・起動セッションの組
func currentClockAnchor() -> ClockAnchor {
    var size = 0
    sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: max(size, 1))
    sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0)
    let boot = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    return ClockAnchor(wall: Date(),
                       monotonicNanos: clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW),
                       bootSessionID: boot)
}

/// 再インストールの印(キーチェーン)。アプリを消しても残ることがある(仕様ではなく実装の挙動=SP-09)。
enum InstallMarker {
    struct Mark: Codable, Equatable {
        var locked: Bool
        var at: Date
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.aokijp.goukakulock",
         kSecAttrAccount as String: "install-marker"]
    }

    static func read() -> Mark? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Mark.self, from: data)
    }

    static func write(_ mark: Mark) {
        guard let data = try? JSONEncoder().encode(mark) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
