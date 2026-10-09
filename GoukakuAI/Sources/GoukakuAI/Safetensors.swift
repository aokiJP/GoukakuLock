import Foundation

/// safetensors から要らないテンソル(画像・音声の部分など)を取り除いて、軽くする。
/// 文章だけを使うので、Qwen3.5 の vision_tower や Gemma 4 の audio_tower/vision_tower を捨てると
/// 大きさが 2〜4 割減る。端末でダウンロードしたあとと、CI で IPA に入れる前の両方で使う。
public enum SafetensorsSlimmer {
    public struct Result: Sendable, Equatable {
        public var kept: Int
        public var dropped: Int
        public var bytesBefore: Int64
        public var bytesAfter: Int64
    }

    public enum SlimError: Error, Equatable {
        case malformed(String)
    }

    struct Entry {
        var name: String
        var info: [String: Any]
        var begin: Int64
        var end: Int64
    }

    /// ヘッダだけを読む(テンソルの名前と、データの位置)
    static func readHeader(_ handle: FileHandle) throws -> (entries: [Entry], metadata: Any?, dataStart: Int64) {
        guard let lengthData = try handle.read(upToCount: 8), lengthData.count == 8 else {
            throw SlimError.malformed("ヘッダの長さが読めない")
        }
        var length: UInt64 = 0
        for (i, byte) in lengthData.enumerated() { length |= UInt64(byte) << (8 * UInt64(i)) }
        guard length > 0, length < 512 * 1024 * 1024 else { throw SlimError.malformed("ヘッダの長さがおかしい") }
        guard let headerData = try handle.read(upToCount: Int(length)), headerData.count == Int(length),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw SlimError.malformed("ヘッダの JSON が読めない")
        }
        var entries: [Entry] = []
        var metadata: Any?
        for (name, value) in header {
            if name == "__metadata__" { metadata = value; continue }
            guard let info = value as? [String: Any], let offsets = info["data_offsets"] as? [Any], offsets.count == 2,
                  let begin = (offsets[0] as? NSNumber)?.int64Value, let end = (offsets[1] as? NSNumber)?.int64Value,
                  end >= begin else {
                throw SlimError.malformed("テンソル \(name) の位置が読めない")
            }
            entries.append(Entry(name: name, info: info, begin: begin, end: end))
        }
        entries.sort { $0.begin < $1.begin }
        return (entries, metadata, 8 + Int64(length))
    }

    /// テンソルの名前の一覧(ヘッダだけ読む)
    public static func tensorNames(at url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try readHeader(handle).entries.map(\.name)
    }

    /// keep が false のテンソルを取り除いた safetensors を output に書く
    @discardableResult
    public static func slim(input: URL, output: URL, keep: (String) -> Bool) throws -> Result {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }
        let (entries, metadata, dataStart) = try readHeader(reader)
        let kept = entries.filter { keep($0.name) }

        var header: [String: Any] = [:]
        if let metadata { header["__metadata__"] = metadata }
        var offset: Int64 = 0
        for entry in kept {
            var info = entry.info
            let size = entry.end - entry.begin
            info["data_offsets"] = [NSNumber(value: offset), NSNumber(value: offset + size)]
            header[entry.name] = info
            offset += size
        }
        var headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        // 8 バイト境界にそろえる(仕様どおり空白で埋める)
        let padding = (8 - headerData.count % 8) % 8
        headerData.append(contentsOf: [UInt8](repeating: 0x20, count: padding))

        let fm = FileManager.default
        try? fm.removeItem(at: output)
        guard fm.createFile(atPath: output.path, contents: nil) else {
            throw SlimError.malformed("書き出し先を作れない")
        }
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }
        var lengthBytes = Data(count: 8)
        let length = UInt64(headerData.count)
        for i in 0..<8 { lengthBytes[i] = UInt8((length >> (8 * UInt64(i))) & 0xFF) }
        try writer.write(contentsOf: lengthBytes)
        try writer.write(contentsOf: headerData)

        let chunk = 8 * 1024 * 1024
        for entry in kept {
            try reader.seek(toOffset: UInt64(dataStart + entry.begin))
            var remaining = Int(entry.end - entry.begin)
            while remaining > 0 {
                guard let data = try reader.read(upToCount: min(chunk, remaining)), !data.isEmpty else {
                    throw SlimError.malformed("テンソル \(entry.name) のデータが途中で切れている")
                }
                try writer.write(contentsOf: data)
                remaining -= data.count
            }
        }
        let before = (try? fm.attributesOfItem(atPath: input.path)[.size] as? NSNumber)?.int64Value ?? 0
        return Result(kept: kept.count, dropped: entries.count - kept.count, bytesBefore: before,
                      bytesAfter: 8 + Int64(headerData.count) + offset)
    }

    /// フォルダの中の safetensors をすべて軽くする(その場で置きかえる)。
    /// 空になったファイルは消し、model.safetensors.index.json があれば合わせて直す
    @discardableResult
    public static func slimDirectory(_ directory: URL, keep: (String) -> Bool) throws -> Result {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "safetensors" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var total = Result(kept: 0, dropped: 0, bytesBefore: 0, bytesAfter: 0)
        var keptNames: [String: String] = [:]   // テンソル名 → ファイル名
        for file in files {
            let names = try tensorNames(at: file)
            guard names.contains(where: { !keep($0) }) else {
                // 捨てるものがなければそのまま
                let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
                total.kept += names.count
                total.bytesBefore += size
                total.bytesAfter += size
                for n in names { keptNames[n] = file.lastPathComponent }
                continue
            }
            let temp = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".slim")
            let result = try slim(input: file, output: temp, keep: keep)
            total.kept += result.kept
            total.dropped += result.dropped
            total.bytesBefore += result.bytesBefore
            if result.kept == 0 {
                try fm.removeItem(at: file)
                try fm.removeItem(at: temp)
            } else {
                try fm.removeItem(at: file)
                try fm.moveItem(at: temp, to: file)
                total.bytesAfter += result.bytesAfter
                for n in names where keep(n) { keptNames[n] = file.lastPathComponent }
            }
        }
        // index.json を直す
        let index = directory.appendingPathComponent("model.safetensors.index.json")
        if let data = try? Data(contentsOf: index),
           var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object["weight_map"] = keptNames
            var meta = object["metadata"] as? [String: Any] ?? [:]
            meta["total_size"] = NSNumber(value: total.bytesAfter)
            object["metadata"] = meta
            let out = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: index, options: .atomic)
        }
        return total
    }
}
