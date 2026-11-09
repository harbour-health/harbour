# Unconfirmed medicine review

## What it is

A visit's Needs review medication items now have a Review medication action. It opens the ordinary medicine editor and requires explicit product/ingredient confirmation before saving; an unknown name never receives inferred ingredients.

## How it works

`VisitMedicineReviewSource` carries the exact source visit, transcript and quote. Existing extractor output uses `name: directions`; grounded portions can prefill the editor. Older free-form items require manual product selection/name entry and retain their text as editable instructions. The demo now uses the same structured display convention as the extractor.

`AppStore.saveMedicine(...reviewSource:)` rechecks the source before writing and commits the medicine, schedule, medicine event and `DoctorVisit.reviewedUnconfirmedQuotes` marker in one protected archive update. A stale or already accepted source cannot save again. Cancellation makes no changes. An accepted item displays Medication saved and does not offer a duplicate acceptance action. Changing a transcript clears its review markers. Existing archives decode the new optional marker as nil.

The reused editor omits the new-product camera controls when reviewing or editing an existing record, putting the product and recorded instructions first. It preserves ingredient uncertainty, supports exact-product selection and keeps its normal confirmation gate. Complex as-needed directions remain text; this workflow does not invent reminder times or establish interaction coverage.

## How to change it

Change source preparation in `VisitMedicineReviewSource.swift`, persistence in `AppStore.saveMedicine`, presentation in `VisitDetailView`, and shared fields in `MedicineEditor`. Keep review status in the same archive write as the actual record. Do not identify an unknown product by guessing from prose. Hosted tests cover persistence, duplicate prevention, stale-source rejection and legacy text; UI tests cover cancellation, explicit confirmation and the saved state.

## Configuration

No new model call, download or permission. The app language selects bundled button labels. Authored demo records support English and French. The source text itself remains in its recorded language.

## Dependencies

HarbourCore DoctorVisit/VisitSummary, existing AppStore and medicine validation, MedicineEditor, and the normal catalogue/manual-product workflow.

## Verification

Hosted tests passed for atomic record/review-status persistence, duplicate acceptance prevention, stale-source rejection and legacy prose. Native UI checks passed for opening the review action, cancelling without accepting, explicitly confirming and saving, and returning to the medication list. The final captures (202–204) are authored demo data; they do not demonstrate model extraction accuracy. Updated labels passed the English/French catalogue audit.
