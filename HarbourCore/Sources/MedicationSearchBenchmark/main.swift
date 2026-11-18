import Dispatch
import Foundation
import HarbourCore

enum BenchmarkError: Error {
    case usage, emptyVocabulary, invalidIterations, outputExists
}

func measure(_ operation: () -> Int, iterations: Int) -> [String: Any] {
    _ = operation()
    var samples: [Double] = []
    var totalResults = 0
    for _ in 0 ..< iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        let count = operation()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        samples.append(Double(elapsed) / 1_000_000)
        totalResults += count
    }
    let sorted = samples.sorted()
    let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2

    return [
        "samples_ms": samples,
        "median_ms": median,
        "p95_ms": sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)],
        "max_ms": sorted.last!,
        "result_count_checksum": totalResults
    ]
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())

    guard arguments.count == 2 || arguments.count == 4, arguments.first == "--output" else {
        throw BenchmarkError.usage
    }

    var iterations = 50
    if arguments.count == 4 {
        guard arguments[2] == "--iterations", let value = Int(arguments[3]), (5 ... 1000).contains(value) else {
            throw BenchmarkError.invalidIterations
        }

        iterations = value
    }
    let output = URL(fileURLWithPath: arguments[1])

    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw BenchmarkError.outputExists
    }

    let start = DispatchTime.now().uptimeNanoseconds
    let vocabulary = MedicationVocabulary.shared
    let coldMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

    guard vocabulary.entries.count > 8000 else {
        throw BenchmarkError.emptyVocabulary
    }

    let queries = [
        ("ibuprofen", "exact_generic"),
        ("Advil", "exact_brand"),
        ("met", "broad_prefix"),
        ("meto", "ambiguous_prefix"),
        ("rosuvastatine", "french_alias"),
        ("acétaminophène", "accented_alias"),
        ("acetaminophene", "unaccented_alias"),
        ("hydroclorothiazide", "generic_deletion"),
        ("metfomrin", "generic_transposition"),
        ("tylneol", "brand_transposition"),
        ("amoxcillin", "generic_typo"),
        ("zzqvxxmedication", "unrelated")
    ]
    var measurements: [[String: Any]] = []
    for (query, category) in queries {
        let operations: [(String, () -> Int)] = [
            ("normal_search", { Catalog.search(query).count }),
            ("suggestions", { vocabulary.suggestions(query).count }),
            ("ui_normal_then_fallback", {
                let exact = Catalog.search(query)

                return exact.isEmpty ? vocabulary.suggestions(query).count : exact.count
            })
        ]
        for (name, operation) in operations {
            var result = measure(operation, iterations: iterations)
            result["query"] = query
            result["category"] = category
            result["operation"] = name
            measurements.append(result)
        }
    }
    #if DEBUG
        let configuration = "debug"
    #else
        let configuration = "release"
    #endif
    let report: [String: Any] = [
        "schema_version": 1,
        "benchmark": "harbour-medication-search-v1",
        "configuration": configuration,
        "source_commit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "unrecorded-local-run",
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "processors": ProcessInfo.processInfo.processorCount,
        "vocabulary_publication_date": vocabulary.publicationDate,
        "vocabulary_entries": vocabulary.entries.count,
        "first_initialization_ms": coldMilliseconds,
        "iterations_per_query_operation": iterations,
        "measurements": measurements,
        "limits": "First construction includes OS file-cache effects. Mac timings do not establish iPhone latency."
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output, options: .withoutOverwriting)
    print("Wrote \(measurements.count) query/operation measurements to \(output.path)")
    print(String(decoding: data, as: UTF8.self))
}

try run()
