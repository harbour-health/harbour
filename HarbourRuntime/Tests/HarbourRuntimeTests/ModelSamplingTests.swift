import Foundation
import XCTest
import llama
@testable import HarbourRuntime

final class ModelSamplingTests: XCTestCase {
    func testInvalidSamplingFailsBeforeTryingToLoadWeights() async {
        let runtime = LocalModel(useGPU: false)
        for settings in [
            ModelSampling(temperature: -.infinity),
            ModelSampling(temperature: .nan),
            ModelSampling(temperature: -0.1),
            ModelSampling(temperature: 3),
            ModelSampling(topP: 0),
            ModelSampling(topK: 0)
        ] {
            do { _ = try await runtime.generate(
                file: URL(fileURLWithPath: "/missing-test-model.gguf"),
                prompt: "test",
                sampling: settings
            )
            XCTFail("Invalid settings accepted") }
            catch ModelError.sampling { }
            catch { XCTFail("Wrong error: \(error)") }
        }
    }

    func testNativeSamplerComponentsInitializeForSeededExperiments() throws {
        for seed: UInt32 in [42, 123, 2026] {
            let samplers = [
                llama_sampler_init_top_k(40),
                llama_sampler_init_top_p(0.95, 1),
                llama_sampler_init_temp(0.2),
                llama_sampler_init_dist(seed)
            ]
            for sampler in samplers {
                llama_sampler_free(try XCTUnwrap(sampler))
            }
        }
    }
}
