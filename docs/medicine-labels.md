# Medicine label scanning

## What it is

Camera or photo-library text recognition inside the existing medicine editor. Extracted text helps fill the form; it never saves a medicine automatically.

## How it works

The camera and photo actions have separate full-width 44-point touch areas. The system camera or Photos picker returns image data. Apple Vision performs accurate text recognition on the device. Exact catalog product matches appear as candidates, and lines beginning with Take/Directions/Dosage/Apply/Use are copied verbatim into editable instructions. The raw label text remains inspectable. A label with several products requires the user to choose the correct one. Unknown products can be entered manually with unconfirmed ingredients.

The user must check the exact product/ingredients before Save. Catalog matches do not prove strength or formulation, and OCR instructions are not prescribing advice. Interactions remain unassessed for unknown ingredients. Invalid/unreadable images clear previous recognition results and show an actionable error.

## How to change it

`MedicineScanner.swift` owns Vision, camera, and Photos picker integration. `CareRules.labelCandidates` and `labelInstructions` provide portable extraction; `MedicineEditor` owns confirmation and atomic persistence. Preserve image orientation by passing the original image data to Vision. Do not map a product to chemical constituents using the LLM.

## Configuration

Recognition languages: English Canada and French Canada. Vision uses `.accurate` recognition with language correction. Camera access uses `NSCameraUsageDescription`; the system Photos picker grants access only to selected images. Debug builds launched with `--qa-label-fixture` show a test-label button and a past initial schedule time for exercising dose logging. That image goes through the real Vision request. The flag is absent in normal launches and fixture controls do not compile into Release.

## Dependencies

Apple Vision, PhotosUI, UIKit camera, SwiftUI, the existing medication catalog. No OCR server or uploaded image.
