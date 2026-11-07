import Foundation
import HarbourCore
import HarbourSpeech

enum SpeechPreferences {
    static let speedKey = "speech.speed"
    static let voiceKey = "speech.kokoroVoice"
    static var speed: Double { SpeechVoiceSelection.speed(UserDefaults.standard.object(forKey: speedKey) as? Double) }
    static var voice: KokoroVoice { KokoroVoice.restored(UserDefaults.standard.string(forKey: voiceKey)) }
}
