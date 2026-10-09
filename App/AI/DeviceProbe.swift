import Foundation
import Metal
import os
import GoukakuAI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// いまの端末の様子を調べる(メモリ・iOS・熱・低電力モード・Apple Intelligence)。
/// どれも端末の中で調べるだけで、どこにも送らない
enum DeviceProbe {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static func current() -> DeviceProfile {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        return DeviceProfile(physicalMemory: info.physicalMemory,
                             availableMemory: availableMemory(),
                             osMajor: version.majorVersion,
                             osMinor: version.minorVersion,
                             model: machineIdentifier(),
                             isSimulator: isSimulator,
                             thermal: thermal(info.thermalState),
                             lowPowerMode: info.isLowPowerModeEnabled,
                             appleIntelligence: appleIntelligence(),
                             supportsMLX: supportsMLX())
    }

    /// GPU が MLX に足りるか(Metal 3:A13 以降。シミュレータは別に見る)
    static func supportsMLX() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsFamily(.metal3)
    }

    /// このアプリがあと使えるメモリ(iOS が教えてくれる値。シミュレータでは使えない)
    static func availableMemory() -> UInt64? {
        #if os(iOS) && !targetEnvironment(simulator)
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
        #else
        return nil
        #endif
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .fair
        }
    }

    static func appleIntelligence() -> AppleIntelligenceState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let availability = SystemLanguageModel.default.availability
            if case .available = availability { return .available }
            if case .unavailable(let reason) = availability {
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .notReady
                @unknown default: return .unavailable
                }
            }
            return .unavailable
        }
        return .unsupportedOS
        #else
        return .unavailable
        #endif
    }

    /// 機種の識別子(例:iPhone17,1)
    static func machineIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// 「8GB」「5.6GB」
    static func gb(_ bytes: UInt64) -> String {
        let value = Double(bytes) / 1_073_741_824
        return value >= 10 || value.rounded() == value ? String(format: "%.0fGB", value) : String(format: "%.1fGB", value)
    }

    static func gb(_ bytes: Int64) -> String { gb(UInt64(max(0, bytes))) }
}
