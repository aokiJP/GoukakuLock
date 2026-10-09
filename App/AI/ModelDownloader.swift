import Foundation
import Observation
import UIKit
import GoukakuAI

/// モデルを Hugging Face からダウンロードして、端末に入れる(初回だけ。以降は通信なしで動く)。
/// 目録で固定したリビジョンのファイルだけを取り、画像・音声の部分を取り除いてから入れる。
/// 途中で止まっても、取り終えたファイルは残して続きから取る
@MainActor @Observable
final class ModelDownloader {
    struct Job: Equatable {
        enum Phase: Equatable {
            case downloading(String)
            case slimming
            case failed(String)
        }

        var received: Int64
        var total: Int64
        var phase: Phase

        var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
        var isActive: Bool {
            if case .failed = phase { return false }
            return true
        }
    }

    private(set) var jobs: [String: Job] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let transfer = FileTransfer()

    var hasActiveJobs: Bool { jobs.values.contains { $0.isActive } }

    func start(_ spec: ModelSpec, allowCellular: Bool, onFinish: @escaping @MainActor (Result<InstalledModel, Error>) -> Void) {
        guard tasks[spec.id] == nil else { return }
        if let free = ModelStore.freeSpace(), free < spec.downloadBytes + spec.installedBytes / 4 {
            jobs[spec.id] = Job(received: 0, total: spec.downloadBytes,
                                phase: .failed("空き容量が足りません(あと \(DeviceProbe.gb(spec.downloadBytes + spec.installedBytes / 4 - free)) 必要)"))
            return
        }
        jobs[spec.id] = Job(received: 0, total: spec.downloadBytes, phase: .downloading(spec.files.first ?? ""))
        UIApplication.shared.isIdleTimerDisabled = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "model-download") {}
        tasks[spec.id] = Task { [weak self] in
            guard let self else { return }
            let result: Result<InstalledModel, Error>
            do {
                result = .success(try await self.run(spec, allowCellular: allowCellular))
            } catch {
                result = .failure(error)
            }
            self.tasks[spec.id] = nil
            switch result {
            case .success:
                self.jobs[spec.id] = nil
            case .failure(let error):
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    self.jobs[spec.id] = nil
                } else {
                    let total = self.jobs[spec.id]?.total ?? spec.downloadBytes
                    self.jobs[spec.id] = Job(received: 0, total: total, phase: .failed(error.localizedDescription))
                }
            }
            if !self.hasActiveJobs { UIApplication.shared.isIdleTimerDisabled = false }
            UIApplication.shared.endBackgroundTask(background)
            onFinish(result)
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs[id] = nil
        if !hasActiveJobs { UIApplication.shared.isIdleTimerDisabled = false }
    }

    func clearFailure(_ id: String) {
        if case .failed? = jobs[id]?.phase { jobs[id] = nil }
    }

    private func run(_ spec: ModelSpec, allowCellular: Bool) async throws -> InstalledModel {
        let fm = FileManager.default
        try fm.createDirectory(at: ModelStore.installedRoot, withIntermediateDirectories: true)
        let staging = ModelStore.installedRoot.appendingPathComponent(".download-\(spec.id)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        ModelStore.excludeFromBackup(staging)

        var finishedBytes: Int64 = 0
        for file in spec.files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file)
            let marker = staging.appendingPathComponent(".\(file).done")
            if fm.fileExists(atPath: marker.path), fm.fileExists(atPath: destination.path) {
                finishedBytes += fileSize(destination)
                jobs[spec.id]?.received = finishedBytes
                continue
            }
            guard let url = spec.url(for: file) else { throw AIError.unavailable("URL が作れません:\(file)") }
            jobs[spec.id]?.phase = .downloading(file)
            let base = finishedBytes
            let written = try await transfer.download(url, to: destination, allowCellular: allowCellular) { [weak self] received in
                Task { @MainActor in self?.jobs[spec.id]?.received = base + received }
            }
            finishedBytes += written
            jobs[spec.id]?.received = finishedBytes
            fm.createFile(atPath: marker.path, contents: Data())
        }

        // 画像・音声の部分を取り除く(重いので裏で)
        jobs[spec.id]?.phase = .slimming
        let keepPrefixes = spec.stripPrefixes
        let stagingURL = staging
        try await Task.detached(priority: .utility) {
            if !keepPrefixes.isEmpty {
                try SafetensorsSlimmer.slimDirectory(stagingURL) { name in !keepPrefixes.contains { name.hasPrefix($0) } }
            }
        }.value

        for file in (try? fm.contentsOfDirectory(atPath: staging.path)) ?? [] where file.hasSuffix(".done") {
            try? fm.removeItem(at: staging.appendingPathComponent(file))
        }
        let manifest = ModelManifest(id: spec.id, name: spec.name, family: spec.family, source: .downloaded,
                                     repo: spec.repo, revision: spec.revision, installedAt: Date(),
                                     bytes: ModelStore.directorySize(staging))
        try manifest.encoded().write(to: staging.appendingPathComponent(ModelManifest.fileName), options: .atomic)
        let destination = ModelStore.installedRoot.appendingPathComponent(spec.id, isDirectory: true)
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
        ModelStore.excludeFromBackup(destination)
        return InstalledModel(manifest: manifest, directory: destination, spec: spec)
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

/// 大きなファイルを1つずつダウンロードする(URLSession の download タスク。進み具合を知らせる)
final class FileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Handler {
        var destination: URL
        var progress: @Sendable (Int64) -> Void
        var continuation: CheckedContinuation<Int64, Error>
        var written: Int64 = 0
        var moveError: Error?
        /// 最後に知らせたバイト数(知らせすぎないよう、4MB ごとにまとめる)
        var reported: Int64 = 0
    }

    private let lock = NSLock()
    private var handlers: [Int: Handler] = [:]
    private var sessions: [Bool: URLSession] = [:]

    private func session(allowCellular: Bool) -> URLSession {
        lock.lock(); defer { lock.unlock() }
        if let existing = sessions[allowCellular] { return existing }
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = allowCellular
        config.allowsExpensiveNetworkAccess = allowCellular
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.httpAdditionalHeaders = ["User-Agent": "GoukakuLock (iOS; on-device AI model download)"]
        let created = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        sessions[allowCellular] = created
        return created
    }

    /// url を destination に保存する。書いたバイト数を返す
    func download(_ url: URL, to destination: URL, allowCellular: Bool,
                  progress: @escaping @Sendable (Int64) -> Void) async throws -> Int64 {
        let task = session(allowCellular: allowCellular).downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
                lock.lock()
                handlers[task.taskIdentifier] = Handler(destination: destination, progress: progress, continuation: continuation)
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        lock.lock()
        guard var handler = handlers[downloadTask.taskIdentifier],
              totalBytesWritten - handler.reported >= 4 * 1_048_576 || totalBytesWritten == totalBytesExpectedToWrite else {
            lock.unlock()
            return
        }
        handler.reported = totalBytesWritten
        handlers[downloadTask.taskIdentifier] = handler
        lock.unlock()
        handler.progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        guard var handler = handlers[downloadTask.taskIdentifier] else { lock.unlock(); return }
        lock.unlock()
        // 一時ファイルはこの中でしか読めないので、すぐ移す
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        if !(200..<300).contains(status) {
            handler.moveError = AIError.unavailable("ダウンロードに失敗しました(HTTP \(status))")
        } else {
            do {
                let fm = FileManager.default
                try? fm.removeItem(at: handler.destination)
                try fm.moveItem(at: location, to: handler.destination)
                handler.written = Int64((try? handler.destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            } catch {
                handler.moveError = error
            }
        }
        lock.lock()
        handlers[downloadTask.taskIdentifier] = handler
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else { lock.unlock(); return }
        lock.unlock()
        if let error {
            handler.continuation.resume(throwing: error)
        } else if let moveError = handler.moveError {
            handler.continuation.resume(throwing: moveError)
        } else {
            handler.continuation.resume(returning: handler.written)
        }
    }
}
