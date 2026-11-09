import XCTest
import HarbourCore
@testable import Harbour

@MainActor final class UnconfirmedMedicineReviewTests: XCTestCase {
    func testReviewSavesUnknownMedicineAndSourceMarkerTogether() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        XCTAssertTrue(store.loadDemoData(french: false))
        let visit = try XCTUnwrap(store.visits.first { $0.summary?.unconfirmedMedicines?.isEmpty == false })
        let item = try XCTUnwrap(visit.summary?.unconfirmedMedicines?.first)
        let source = VisitMedicineReviewSource(visit: visit, item: item)
        let medicine = try XCTUnwrap(source.medicine(saved: store.records.medicines))
        XCTAssertEqual(medicine.name, "salbutamol")
        XCTAssertTrue(medicine.ingredients.isEmpty)
        XCTAssertTrue(medicine.instructions.contains("maximum 8 puffs in 24 hours"))
        XCTAssertTrue(store.saveMedicine(medicine, schedule: nil, reviewSource: source))
        XCTAssertEqual(store.visits.first { $0.id == visit.id }?.reviewedUnconfirmedQuotes, [item.quote])
        XCTAssertFalse(store.saveMedicine(medicine, schedule: nil, reviewSource: source))
        let reloaded = AppStore(folder: folder)
        XCTAssertTrue(reloaded.records.medicines.contains { $0.id == medicine.id })
        XCTAssertEqual(reloaded.visits.first { $0.id == visit.id }?.reviewedUnconfirmedQuotes, [item.quote])
    }

    func testChangedSourceRejectsSaveAndLegacyProseDoesNotGuessIngredients() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AppStore(folder: folder)
        XCTAssertTrue(store.loadDemoData(french: false))
        var visit = try XCTUnwrap(store.visits.first { $0.summary?.unconfirmedMedicines?.isEmpty == false })
        let item = try XCTUnwrap(visit.summary?.unconfirmedMedicines?.first)
        let source = VisitMedicineReviewSource(visit: visit, item: item)
        let original = store.records.medicines
        visit.transcript += " Changed."
        XCTAssertTrue(store.saveVisit(visit))
        XCTAssertFalse(store.saveMedicine(
            try XCTUnwrap(source.medicine(saved: original)),
            schedule: nil,
            reviewSource: source
        ))
        XCTAssertEqual(store.records.medicines, original)
        let legacy = VisitMedicineReviewSource(
            visit: visit,
            item: VisitQuote(
                quote: "Some unfamiliar product was discussed.",
                text: "Some unfamiliar product was discussed."
            )
        )
        XCTAssertTrue(legacy.name.isEmpty)
        XCTAssertNil(legacy.medicine(saved: original))
    }
}
