# Appointments

Appointments are records with a title, date, optional clock time, location, and notes. Records has a dedicated Appointments category with add/edit and swipe deletion. Upcoming appointments also appear on Today and in timeline searches.

The chat tools are `create_appointment` and `list_appointments`. Creating an appointment opens the same editor as manual entry. Model arguments cannot supply facts: the draft uses the original message. Literal ISO dates, tomorrow/demain, a single named weekday, and an explicit clock time can prefill the date. Weekdays mean the next occurrence. Ambiguous or absent dates remain for the user to choose. New drafts always require date confirmation before Save; existing appointments can be edited directly.

Visit summaries request an `appointments` array of exact quotes. Source sentences provide a fallback when the model omits the category. Negated and hypothetical sentences are filtered before they become proposals. Choosing Add appointment opens an editable draft; relative dates use the visit date as their reference. The draft retains the visit ID and quote. Saving revalidates that source, and editing/deleting the visit detaches invalid associations without deleting the saved appointment.

Appointments are included in version 2 record backups. Imports validate dates, field lengths, unique IDs, and source associations before an atomic merge. Older record files decode with an empty appointment list. New saved records use the `medications` key; the old `medicines` key remains readable. Existing internal medicine types and visit-summary JSON retain their legacy names for compatibility.

Core tests cover grounding, rejected proposals, English/French conditionals, abbreviated times, reference dates, migration, and imports. Hosted tests cover persistence, export/import, and stale sources. The simulator smoke test covers manual entry, date confirmation, saving, and relaunch.
