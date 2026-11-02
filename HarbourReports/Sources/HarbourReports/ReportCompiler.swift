import Foundation
import TypstBridge

public enum ReportCompilerError: Error { case missingTemplate, invalidInput, compilation(String) }

/// Serializes compilation away from the UI; the renderer can only read the supplied JSON.
public actor ReportCompiler {
    public static let shared = ReportCompiler()
    public func compile(json: Data) throws -> Data {
        guard !json.isEmpty, json.count <= 5_000_000 else { throw ReportCompilerError.invalidInput }
        guard let url = Bundle.module.url(forResource: "visit-report", withExtension: "typ") else { throw ReportCompilerError.missingTemplate }
        let template = try Data(contentsOf: url)
        var output: UnsafeMutablePointer<UInt8>?
        var count = 0
        let status = template.withUnsafeBytes { source in
            json.withUnsafeBytes { input in
                harbour_typst_compile(source.bindMemory(to: UInt8.self).baseAddress!, template.count,
                                      input.bindMemory(to: UInt8.self).baseAddress!, json.count, &output, &count)
            }
        }
        guard let output else { throw ReportCompilerError.compilation("No report produced") }
        defer { harbour_typst_free(output, count) }
        let data = Data(bytes: output, count: count)
        guard status == 0 else { throw ReportCompilerError.compilation(String(decoding: data, as: UTF8.self)) }
        return data
    }
}
