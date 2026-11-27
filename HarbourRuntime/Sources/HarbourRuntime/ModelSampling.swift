import Foundation

/// Greedy by default; seeded sampling is opt-in for controlled evaluation.
public struct ModelSampling: Sendable, Equatable {
    public var temperature: Float
    public var topP: Float
    public var topK: Int32
    public var seed: UInt32
    public init(temperature: Float = 0, topP: Float = 0.95, topK: Int32 = 40, seed: UInt32 = 42) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.seed = seed
    }

    public static let greedy = ModelSampling()
    public var isValid: Bool {
        temperature.isFinite && (0 ... 2).contains(temperature) && topP.isFinite && topP > 0 && topP <= 1 && topK > 0 }
}
