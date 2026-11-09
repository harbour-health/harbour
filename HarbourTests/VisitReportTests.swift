import XCTest
import PDFKit
import HarbourCore
import HarbourReports
@testable import Harbour

@MainActor final class VisitReportTests: XCTestCase {
    func testReportFiltersWholeDaysAndSelectedSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        var records = Records()
        records.readings = [
            Reading(kind: .heartRate, value: "71", date: start),
            Reading(kind: .heartRate, value: "72", date: now),
            Reading(kind: .heartRate, value: "99", date: start.addingTimeInterval(-1)),
            Reading(kind: .heartRate, value: "98", date: now.addingTimeInterval(60))
        ]
        records.medicines = [Medicine(name: "Should be excluded")]
        let snapshot = VisitReportSnapshot(
            records: records,
            care: CareData(),
            visits: [],
            from: start.addingTimeInterval(3600),
            through: now,
            selected: [.readings],
            detailed: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(snapshot.sections[0].items.count, 2)
        XCTAssertEqual(snapshot.sections[0].charts.count, 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
            .contains("Should be excluded"))
    }

    func testEmbeddedTypstRendersMultipagePDFWithLiteralPersonalText() async throws {
        var records = Records()
        var care = CareData()
        let now = Date.now
        let literal = "#panic(\"never execute\") [notes] <tag> Émilie & François"
        records.symptoms = [Symptom(text: literal, onset: "Tuesday", severity: "Mild", date: now)]
        for index in 0 ..< 9 {
            records.readings.append(Reading(
                kind: .bloodPressure,
                value: "\(120 + index)/\(80 + index)",
                date: now.addingTimeInterval(Double(index - 9) * 3600)
            ))
        }
        care.questions = (1 ... 100)
            .map {
                AppointmentQuestion(text: "Question \($0): Discuss my recorded information at the next appointment.") }
        let snapshot = VisitReportSnapshot(
            records: records,
            care: care,
            visits: [],
            from: now.addingTimeInterval(-86400),
            through: now,
            selected: Set(VisitReportSection.allCases),
            detailed: true,
            now: now
        )
        let data = try await ReportCompiler.shared.compile(json: JSONEncoder().encode(snapshot))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        let text = try XCTUnwrap(document.string)
        XCTAssertTrue(text.contains("never execute"))
        XCTAssertTrue(text.contains("Émilie & François"))
        XCTAssertTrue(text.contains("Question 100"))
        XCTAssertTrue(text.contains("120/80"))
        let repeated = try await ReportCompiler.shared.compile(json: JSONEncoder().encode(snapshot))
        XCTAssertEqual(
            PDFDocument(data: repeated)?.string,
            text,
            "Repeated exports must preserve all text after cache cleanup"
        )
        // Export only fictional fixture records for visual inspection.
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Harbour-report-test.pdf"))
        }
    }

    func testCompilerRejectsInvalidAndOversizedInput() async {
        for json in [Data(), Data("not JSON".utf8), Data(repeating: 32, count: 5_000_001)] {
            do { _ = try await ReportCompiler.shared.compile(json: json)
                XCTFail("Invalid input should fail") } catch {}
        }
    }
}

@MainActor final class CondensedReportTests: XCTestCase {
    func testSummaryReportIsBoundedAndKeepsEveryCurrentMedication() async throws {
        let now = Date.now, demo = DemoData.make(now: now, french: false)
        let start = now.addingTimeInterval(-60 * 86400)
        let summary = VisitReportSnapshot(
            records: demo.records,
            care: demo.care ?? CareData(),
            visits: demo.visits ?? [],
            from: start,
            through: now,
            selected: Set(VisitReportSection.allCases),
            now: now
        )
        let complete = VisitReportSnapshot(
            records: demo.records,
            care: demo.care ?? CareData(),
            visits: demo.visits ?? [],
            from: start,
            through: now,
            selected: Set(VisitReportSection.allCases),
            detailed: true,
            now: now
        )
        XCTAssertEqual(summary.sections[0].items.count, 3)
        XCTAssertEqual(complete.sections[0].items.count, 126)
        XCTAssertEqual(summary.sections[2].items.count, demo.records.medicines.count)
        XCTAssertTrue(summary.sections[0].items.allSatisfy { $0.detail.contains("42 readings") })
        let data = try await ReportCompiler.shared.compile(json: JSONEncoder().encode(summary))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertLessThanOrEqual(pdf.pageCount, 4)
        let text = (0 ..< pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(text.contains("Metformin"))
        XCTAssertTrue(text.contains("breakfast and dinner"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "condensed-doctor-visit-report"
        attachment.lifetime = .keepAlways
        add(attachment)
        for index in 0 ..< pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            let a = XCTAttachment(image: page.thumbnail(of: CGSize(width: 900, height: 1200), for: .mediaBox))
            a.name = "condensed-report-page-\(index + 1)"
            a.lifetime = .keepAlways
            add(a)
        }
    }
}
