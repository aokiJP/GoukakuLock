import Foundation
import UIKit

/// 証拠写真の置き場所(Application Support/evidence/)。端末の外には出さない。
/// 保存するのは縮めた JPEG だけで、撮影時の位置情報などのメタデータは入らない(仕様書 第6.2節)。
@MainActor
enum EvidenceStore {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("evidence", isDirectory: true)
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// 長辺 1600px に縮めて保存し、ファイル名を返す
    static func save(_ image: UIImage) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: url(for: fileName), options: [.atomic, .completeFileProtection])
        return fileName
    }

    static func image(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    /// 既定 90 日より古い写真を消す(起動のたびに呼ぶ)
    static func removeOlderThan(days: Int, now: Date = Date()) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let limit = now.addingTimeInterval(-TimeInterval(days) * 86_400)
        for name in names {
            let url = url(for: name)
            let created = (try? fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? now
            if created < limit { try? fm.removeItem(at: url) }
        }
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
