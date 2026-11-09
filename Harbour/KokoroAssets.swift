import Foundation
import CryptoKit
import HarbourSpeech

@MainActor final class KokoroAssets: ObservableObject {
    static let shared = KokoroAssets()
    @Published private(set) var downloading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var ready = false
    @Published private(set) var error: String?
    private var work: Task<URL, Error>?
    private var download: ModelDownload?
    let directory: URL
    private struct Asset: Sendable { var name: String, url: String, hash: String
        var bytes: Int64 }

    private static let assets: [Asset] = [
        .init(
            name: "kokoro-v1.0.onnx",
            url: "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.onnx",
            hash: "beb0d1848dee9a49da392cc3df26958d46cfa35d321edf434f52949153f0df3a",
            bytes: 325505369
        ),
        .init(
            name: "af_heart.bin",
            url: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/voices/af_heart.bin",
            hash: "d583ccff3cdca2f7fae535cb998ac07e9fcb90f09737b9a41fa2734ec44a8f0b",
            bytes: 522240
        ),
        .init(
            name: "am_liam.bin",
            url: "https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX/resolve/1939ad2a8e416c0acfeecc08a694d14ef25f2231/voices/am_liam.bin",
            hash: "52403be32fd047c6a44517cb0bcd6b134f2a18baa73e70ef41651e0eab921ade",
            bytes: 522240
        )
    ]
    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                "Voices/Kokoro",
                isDirectory: true
            )
        ready = Self.assets.allSatisfy { Self.cached($0, in: directory) }
    }

    func voiceFile(_ voice: KokoroVoice) -> URL {
        directory.appendingPathComponent(voice.rawValue + ".bin")
    }

    func cancel() {
        work?.cancel()
        download?.cancel() }

    func ensure() async throws -> URL {
        if let work {
            return try await work.value
        }
        downloading = true
        error = nil
        let task = Task { @MainActor in
            defer { self.downloading = false
                self.download = nil
                self.work = nil }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var url = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try url.setResourceValues(values)
                let total = Double(Self.assets.reduce(Int64(0)) { $0 + $1.bytes })
                var completed: Int64 = 0
                for asset in Self.assets {
                    try Task.checkCancellation()
                    let destination = directory.appendingPathComponent(asset.name)
                    if !Self.cached(asset, in: directory) {
                        let temporary = directory.appendingPathComponent(UUID().uuidString + ".download")
                        defer { try? FileManager.default.removeItem(at: temporary) }
                        let base = completed
                        let downloader = ModelDownload(destination: temporary) { [weak self] value in
                            Task { @MainActor in self?.progress = (Double(base) + value * Double(asset.bytes)) / total }
                        }
                        download = downloader
                        _ = try await downloader.start(URL(string: asset.url)!)
                        try Task.checkCancellation()
                        let valid = try await Task.detached(priority: .utility) { try Self.verify(
                            temporary,
                            asset: asset
                        ) }.value

                        guard valid else {
                            throw KokoroError.assets
                        }

                        try Task.checkCancellation()
                        if
                            FileManager.default
                                .fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.moveItem(at: temporary, to: destination)
                        try Data(asset.hash.utf8).write(
                            to: destination.appendingPathExtension("verified"),
                            options: .atomic
                        )
                    }
                    completed += asset.bytes
                    progress = Double(completed) / total
                }
                ready = true

                return directory.appendingPathComponent("kokoro-v1.0.onnx")
            } catch {
                if !Task.isCancelled {
                    self.error = L10n.string(error.localizedDescription)
                }

                throw error }
        }
        work = task

        return try await task.value
    }

    private nonisolated static func cached(_ asset: Asset, in directory: URL) -> Bool {
        let file = directory.appendingPathComponent(asset.name)

        return (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(asset.bytes)
            && (try? String(contentsOf: file.appendingPathExtension("verified"), encoding: .utf8)) == asset.hash
    }

    private nonisolated static func verify(_ file: URL, asset: Asset) throws -> Bool {
        guard
            (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(asset.bytes),
            let stream = InputStream(url: file) else {
            return false
        }

        stream.open()
        defer { stream.close() }
        var digest = SHA256(), buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? KokoroError.assets
            }
            if count == 0 {
                break
            }
            digest.update(data: Data(buffer.prefix(count)))
        }

        return digest.finalize().map { String(format: "%02x", $0) }.joined() == asset.hash
    }
}
