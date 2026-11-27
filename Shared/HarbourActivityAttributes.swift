import ActivityKit
import Foundation

struct HarbourActivityAttributes: ActivityAttributes {
    enum Mode: String, Codable, Hashable { case recording, voice }
    enum Phase: String, Codable, Hashable {
        case recording, paused, listening, finishing, thinking, speaking, ended
        func title(french: Bool) -> String {
            switch self {
            case .recording: french ? "Enregistrement" : "Recording"
            case .paused: french ? "En pause" : "Paused"
            case .listening: french ? "À l’écoute" : "Listening"
            case .finishing: french ? "Traitement…" : "Finishing…"
            case .thinking: french ? "Réflexion…" : "Thinking…"
            case .speaking: french ? "Lecture à voix haute" : "Speaking"
            case .ended: french ? "Terminé" : "Ended"
            }
        }

        var symbol: String {
            switch self {
            case .recording: "mic.fill"
            case .paused: "pause.fill"
            case .listening: "waveform"
            case .finishing, .thinking: "ellipsis"
            case .speaking: "speaker.wave.2.fill"
            case .ended: "checkmark"
            }
        }
    }

    struct ContentState: Codable, Hashable {
        var phase: Phase
        var elapsed: TimeInterval
        var timerStart: Date?
    }

    var sessionID: UUID
    var mode: Mode
    var french: Bool
    var title: String {
        mode == .recording ? (french ? "Enregistrement" : "Recording") :
            (french ? "Conversation vocale" : "Voice conversation") }

    var url: URL {
        URL(string: mode == .recording ? "harbour://recording" : "harbour://chat")!
    }
}
