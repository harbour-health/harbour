# Simple interface and presentation

The app defaults to larger Simple-mode actions, with caregiver records available through Settings → Interface. Both modes share the existing agent, record editors, speech services and local data. Home counts were removed and common action sizes increased.

The compact official bilingual DPD vocabulary adds exact name lookup, confirmed phonetic suggestions and bounded speech context. It expands names, not interaction-rule coverage. Source ZIP/resource hashes and scope are recorded in the medication-vocabulary manifest. No new model weights were downloaded for this work.

The presentation uses genuine native footage and UI crops outside the phone, with Touying slides and editable source scripts. The native app has no visible presenter overlay. The first zoom experiment was superseded by the external deconstruction requested during review.

## Verification

- 153 HarbourCore tests passed.
- Simple English/French, mode switching and largest accessibility text: three native UI tests passed.
- Clean end-to-end native walkthrough passed, including a real Alex tool call, name suggestion selection, visible confirmation form and visit review.
- Hosted conversation/demo/correction/review suites: 13 unique tests passed; the audio file-protection test skipped because Simulator does not expose iOS protection attributes. Real Sam dose-correction and uncertain-name tests passed. The old salbutamol-as-unknown assertion was replaced by an exact database-identity assertion, with a separate genuinely unknown fictional-product test.
- Alex/Sam medication-name subset: 14/16 complete outcomes each. Both negation routes failed, and source validation blocked all attempted changes. See the raw reports and evaluation doc.

The filename-specific capture/export logs and test results remain local under `/private/tmp`; runtime console noise is not shipped as documentation. Acoustic speech accuracy, physical-device encryption policy, older-adult usability and new clinical summary accuracy remain unmeasured by these checks.

## How to change, configuration and dependencies

See [interfaces](../simple-and-caregiver.md), [vocabulary](../medication-vocabulary.md), [presentation](../presentation-walkthrough.md) and [testing](../testing.md) for source locations, configuration and reproduction. Existing app lock, automatic model selection and native background recording behavior are preserved. This change does not change the bundle identifier or publish the app.
