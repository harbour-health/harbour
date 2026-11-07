import Foundation

/// Platform-neutral ranking of the voices the device reports as available.
public struct SpeechVoiceCandidate: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let language: String
    public let quality: Int
    public init(identifier: String, name: String, language: String, quality: Int) {
        self.identifier = identifier; self.name = name; self.language = language; self.quality = quality
    }
}

public enum SpeechVoiceSelection {
    public static func ranked(_ voices: [SpeechVoiceCandidate], locale: String) -> [SpeechVoiceCandidate] {
        let language = locale.split(separator: "-").first
        return voices.filter { $0.language.split(separator: "-").first == language }.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            if ($0.language == locale) != ($1.language == locale) { return $0.language == locale }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.identifier < $1.identifier
        }
    }

    public static func selected(_ voices: [SpeechVoiceCandidate], locale: String, preferredIdentifier: String) -> SpeechVoiceCandidate? {
        let available = ranked(voices, locale: locale)
        return available.first { $0.identifier == preferredIdentifier } ?? available.first
    }

    public static func speed(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 1 }
        return min(1.3, max(0.8, value))
    }
}
