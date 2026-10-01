import Foundation
import AVFoundation
import HarbourCore

enum SpeechPreferences {
    static let speedKey = "speech.speed"
    static var voiceKey: String { "speech.voice." + SpeechLanguage.identifier }
    static var speed: Double { SpeechVoiceSelection.speed(UserDefaults.standard.object(forKey: speedKey) as? Double) }
    static var availableVoices: [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let ranked = SpeechVoiceSelection.ranked(voices.map(candidate), locale: SpeechLanguage.identifier)
        let byID = Dictionary(voices.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return ranked.compactMap { byID[$0.identifier] }
    }
    static var selectedVoice: AVSpeechSynthesisVoice? {
        let voices = availableVoices
        let identifier = UserDefaults.standard.string(forKey: voiceKey) ?? ""
        return voices.first { $0.identifier == identifier } ?? voices.first
    }
    private static func candidate(_ voice: AVSpeechSynthesisVoice) -> SpeechVoiceCandidate {
        SpeechVoiceCandidate(identifier: voice.identifier, name: voice.name, language: voice.language, quality: voice.quality.rawValue)
    }
    static func details(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = L10n.string("Premium")
        case .enhanced: quality = L10n.string("Enhanced")
        default: quality = L10n.string("Standard")
        }
        let language = L10n.locale.localizedString(forIdentifier: voice.language) ?? voice.language
        return language + " · " + quality
    }
}
