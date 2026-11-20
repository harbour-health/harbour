import AVFoundation
import Foundation

// Codec diagnostics only: generated silence is not microphone or ASR evidence.
func probe(_ url: URL, format: AVAudioFormat, bitRate: Int?, stage: inout String) throws -> [String: Any] {
    var settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: format.sampleRate,
        AVNumberOfChannelsKey: format.channelCount
    ]
    if let bitRate {
        settings[AVEncoderBitRateKey] = bitRate
    }
    let frames = AVAudioFrameCount(format.sampleRate / 10)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0 ..< Int(format.channelCount) {
        buffer.floatChannelData![channel].initialize(repeating: 0, count: Int(frames))
    }
    var writer: AVAudioFile? = try AVAudioFile(
        forWriting: url, settings: settings, commonFormat: format.commonFormat,
        interleaved: format.isInterleaved
    )
    stage = "writing_pcm"
    try writer!.write(from: buffer)
    writer = nil
    stage = "opening_readback"
    let reader = try AVAudioFile(forReading: url)
    let decoded = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: frames)!
    stage = "decoding_readback"
    try reader.read(into: decoded)

    guard decoded.frameLength > 0 else {
        throw NSError(
            domain: "HarbourAudioProbe",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Readback decoded no audio frames"]
        )
    }

    stage = "complete"

    return [
        "written_pcm_frames": frames,
        "decoded_frames": decoded.frameLength,
        "file_frames": reader.length,
        "file_format": reader.fileFormat.description,
        "processing_format": reader.processingFormat.description,
        "file_bytes": try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    ]
}

func run() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("harbour-aac-probe-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    var results: [[String: Any]] = []
    let channelCounts: [AVAudioChannelCount] = [1, 2]
    let bitRates: [Int?] = [32000, 64000, nil]
    for rate in [16000.0, 44100.0, 48000.0] {
        for channels in channelCounts {
            for bitRate in bitRates {
                let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: rate,
                    channels: channels,
                    interleaved: false
                )!
                var row: [String: Any] = [
                    "sample_rate": rate, "channels": channels, "pcm_format": "float32",
                    "interleaved": false, "duration_seconds": 0.1,
                    "bit_rate_policy": bitRate == nil ? "platform_default" : "explicit"
                ]
                if let bitRate {
                    row["requested_bit_rate"] = bitRate
                }
                let url = directory.appendingPathComponent(UUID().uuidString + ".m4a")
                var stage = "creating_writer"
                do {
                    row["readback"] = try probe(url, format: format, bitRate: bitRate, stage: &stage)
                    row["status"] = "ok"
                } catch {
                    let error = error as NSError
                    row["status"] = "error"
                    row["error_domain"] = error.domain
                    row["error_code"] = error.code
                    row["error_description"] = error.localizedDescription
                }
                row["stage"] = stage
                results.append(row)
            }
        }
    }
    let report: [String: Any] = [
        "schema_version": 1, "probe": "harbour-aac-writer-v1",
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "source_commit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "unrecorded-local-run",
        "evidence": "Synthetic zero PCM tests AAC encode/decode only; no microphone, permissions, human speech or ASR.",
        "results": results
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))

    // The recording writer uses the platform default. Explicit rates above are diagnostics.
    let failedDefaults = results.filter {
        $0["bit_rate_policy"] as? String == "platform_default" && $0["status"] as? String != "ok"
    }
    if !failedDefaults.isEmpty {
        throw NSError(
            domain: "HarbourAudioProbe",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Default AAC settings failed encode/decode; see format results above"]
        )
    }
}

try run()
