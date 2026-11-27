# Candidate case matrix

| Model | Variant | Case | Pass | Review flag | Failures |
| --- | --- | --- | --- | --- | --- |
| 1.5B | One pass | switch-en | False |  | plan count 1, expected 2; naproxen: scope negated, expected affirmed; missing medication:acetaminophen |
| 1.5B | One pass | switch-fr | False |  | plan count 1, expected 2; missing medication:acétaminophène |
| 1.5B | One pass | taper-en | False |  | plan count 0, expected 1; missing medication:prednisone; unsupportedEvidence |
| 1.5B | One pass | taper-fr | False |  | plan count 0, expected 1; missing medication:prednisone; unsupportedEvidence |
| 1.5B | One pass | conditional-course-en | False |  | plan count 0, expected 1; missing medication:insulin; unsupportedEvidence |
| 1.5B | One pass | conditional-course-fr | False |  | plan count 0, expected 1; missing medication:insuline; unsupportedEvidence |
| 1.5B | One pass | followups-en | False |  | plan count 1, expected 2; : missing structured timing in nine days; : scope conditional, expected affirmed; : missing potassium; : missing in nine days; missing followUp: |
| 1.5B | One pass | followups-fr | False |  | plan count 0, expected 2; missing followUp:; missing followUp:; unsupportedEvidence |
| 1.5B | One pass | negation-en | False |  | ramipril: missing structured condition unless the clinic calls you; ramipril: scope negated, expected conditional |
| 1.5B | One pass | negation-fr | False |  | ramipril: missing structured condition sauf si la clinique vous appelle; ramipril: scope negated, expected conditional |
| 1.5B | One pass | approval-en | False |  | metformin: action start, expected update; metformin: missing structured condition only after your pharmacist confirms the change; metformin: missing structured timing with breakfast; metformin: scope affirmed, expected conditional |
| 1.5B | One pass | approval-fr | False |  | metformine: action start, expected update; metformine: missing structured condition seulement après confirmation du changement par votre pharmacien; metformine: missing structured timing avec le déjeuner; metformine: scope affirmed, expected conditional |
| 1.5B | One pass | alternating-en | False |  | plan count 0, expected 1; missing medication:warfarin; unsupportedEvidence |
| 1.5B | One pass | alternating-fr | False |  | missing medication:warfarine |
| 1.5B | One pass | empty-en | False |  | plan count 1, expected 0 |
| 1.5B | One pass | empty-fr | False |  | plan count 1, expected 0 |
| 7B | One pass | switch-en | False |  | plan count 0, expected 2; missing medication:naproxen; missing medication:acetaminophen; invalidSequence |
| 7B | One pass | switch-fr | False |  | plan count 1, expected 2; missing medication:naproxène |
| 7B | One pass | taper-en | False |  | prednisone: 1 phases, expected 3 |
| 7B | One pass | taper-fr | False |  | prednisone: 1 phases, expected 3 |
| 7B | One pass | conditional-course-en | True |  |  |
| 7B | One pass | conditional-course-fr | True |  |  |
| 7B | One pass | followups-en | False |  | : 2 phases, expected 1 |
| 7B | One pass | followups-fr | False |  | : missing structured timing dans neuf jours; : scope conditional, expected affirmed |
| 7B | One pass | negation-en | False |  | ramipril: action continue, expected stop |
| 7B | One pass | negation-fr | False |  | plan count 0, expected 1; missing medication:ramipril; unsupportedEvidence |
| 7B | One pass | approval-en | False |  | metformin: action start, expected update; metformin: missing structured timing with breakfast |
| 7B | One pass | approval-fr | False |  | metformine: action start, expected update; metformine: missing structured condition seulement après confirmation du changement par votre pharmacien; metformine: missing structured timing avec le déjeuner |
| 7B | One pass | alternating-en | True |  |  |
| 7B | One pass | alternating-fr | True |  |  |
| 7B | One pass | empty-en | False |  | plan count 1, expected 0 |
| 7B | One pass | empty-fr | False |  | plan count 1, expected 0 |
| 1.5B | Linked | switch-en | False | False | plan count 1, expected 2; missing medication:naproxen; missing medication:acetaminophen |
| 1.5B | Linked + coverage | switch-en | False | False | plan count 1, expected 2; missing medication:naproxen; missing medication:acetaminophen |
| 1.5B | Linked | switch-fr | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxène; missing medication:acétaminophène |
| 1.5B | Linked + coverage | switch-fr | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxène; missing medication:acétaminophène |
| 1.5B | Linked | taper-en | False | False | prednisone: missing structured repetition each morning; prednisone: missing structured duration for two days; prednisone: missing structured duration for three days; prednisone: 1 phases, expected 3; prednisone: missing 25 mg; prednisone: missing two days; prednisone: missing 15 mg; prednisone: missing three days |
| 1.5B | Linked + coverage | taper-en | False | False | prednisone: missing structured repetition each morning; prednisone: missing structured duration for two days; prednisone: missing structured duration for three days; prednisone: 2 phases, expected 3 |
| 1.5B | Linked | taper-fr | False | False | prednisone: missing structured repetition chaque matin; prednisone: missing structured duration pendant deux jours; prednisone: missing structured duration pendant trois jours; prednisone: 1 phases, expected 3 |
| 1.5B | Linked + coverage | taper-fr | False | False | prednisone: missing structured repetition chaque matin; prednisone: missing structured duration pendant deux jours; prednisone: missing structured duration pendant trois jours; prednisone: 1 phases, expected 3 |
| 1.5B | Linked | conditional-course-en | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 1; missing medication:insulin |
| 1.5B | Linked + coverage | conditional-course-en | False | True | unit 0: evidence; unit 1: evidence; missing medication:insulin |
| 1.5B | Linked | conditional-course-fr | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 1; missing medication:insuline |
| 1.5B | Linked + coverage | conditional-course-fr | False | True | unit 0: evidence; unit 1: evidence; unit 1: evidence; missing medication:insuline |
| 1.5B | Linked | followups-en | False | True | unit 1: evidence; plan count 1, expected 2; missing followUp:; missing followUp: |
| 1.5B | Linked + coverage | followups-en | False | True | unit 1: evidence; unit 0: evidence; unit 1: evidence; plan count 1, expected 2; missing followUp:; missing followUp: |
| 1.5B | Linked | followups-fr | False | True | unit 1: evidence; link: grouping; plan count 0, expected 2; missing followUp:; missing followUp: |
| 1.5B | Linked + coverage | followups-fr | False | True | unit 1: evidence; unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 2; missing followUp:; missing followUp: |
| 1.5B | Linked | negation-en | False | True | link: grouping; plan count 0, expected 1; missing medication:ramipril |
| 1.5B | Linked + coverage | negation-en | False | True | link: grouping; plan count 0, expected 1; missing medication:ramipril |
| 1.5B | Linked | negation-fr | False | False | missing medication:ramipril |
| 1.5B | Linked + coverage | negation-fr | False | False | missing medication:ramipril |
| 1.5B | Linked | approval-en | False | False | missing medication:metformin |
| 1.5B | Linked + coverage | approval-en | False | False | missing medication:metformin |
| 1.5B | Linked | approval-fr | False | False | missing medication:metformine |
| 1.5B | Linked + coverage | approval-fr | False | False | missing medication:metformine |
| 1.5B | Linked | alternating-en | False | True | link: grouping; plan count 0, expected 1; missing medication:warfarin |
| 1.5B | Linked + coverage | alternating-en | False | True | link: grouping; plan count 0, expected 1; missing medication:warfarin |
| 1.5B | Linked | alternating-fr | True | False |  |
| 1.5B | Linked + coverage | alternating-fr | True | False |  |
| 1.5B | Linked | empty-en | False | True | unit 0: evidence; link: grouping |
| 1.5B | Linked + coverage | empty-en | False | True | unit 0: evidence; link: grouping |
| 1.5B | Linked | empty-fr | False | True | unit 0: evidence; link: grouping |
| 1.5B | Linked + coverage | empty-fr | False | True | unit 0: evidence; link: grouping |
| 7B | Linked | switch-en | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxen; missing medication:acetaminophen |
| 7B | Linked + coverage | switch-en | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxen; missing medication:acetaminophen |
| 7B | Linked | switch-fr | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxène; missing medication:acétaminophène |
| 7B | Linked + coverage | switch-fr | False | True | link: grouping; plan count 0, expected 2; missing medication:naproxène; missing medication:acétaminophène |
| 7B | Linked | taper-en | False | False | prednisone: missing structured repetition each morning; prednisone: missing structured duration for two days; prednisone: missing structured duration for three days; prednisone: 1 phases, expected 3 |
| 7B | Linked + coverage | taper-en | False | False | prednisone: missing structured repetition each morning; prednisone: missing structured duration for two days; prednisone: missing structured duration for three days; prednisone: 2 phases, expected 3 |
| 7B | Linked | taper-fr | False | True | unit 0: evidence; link: grouping; plan count 0, expected 1; missing medication:prednisone |
| 7B | Linked + coverage | taper-fr | False | True | unit 0: evidence; prednisone: missing structured repetition chaque matin; prednisone: missing structured duration pendant deux jours; prednisone: missing structured duration pendant trois jours; prednisone: 1 phases, expected 3 |
| 7B | Linked | conditional-course-en | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 1; missing medication:insulin |
| 7B | Linked + coverage | conditional-course-en | False | True | unit 0: evidence; unit 1: evidence; unit 1: evidence; insulin: missing structured condition only if morning glucose remains above 10 mmol/L; insulin: missing structured timing at bedtime; insulin: missing structured timing After four days; insulin: 1 phases, expected 2; insulin: missing four days; insulin: missing 11 units; insulin: missing only if morning glucose remains above 10 mmol/L |
| 7B | Linked | conditional-course-fr | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 1; missing medication:insuline |
| 7B | Linked + coverage | conditional-course-fr | False | True | unit 0: evidence; unit 1: evidence; unit 1: evidence; missing medication:insuline |
| 7B | Linked | followups-en | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 2; missing followUp:; missing followUp: |
| 7B | Linked + coverage | followups-en | False | True | unit 0: evidence; unit 1: evidence; unit 1: evidence; plan count 1, expected 2; : missing structured timing in nine days; missing followUp: |
| 7B | Linked | followups-fr | False | True | unit 0: evidence; unit 1: evidence; link: grouping; plan count 0, expected 2; missing followUp:; missing followUp: |
| 7B | Linked + coverage | followups-fr | False | True | unit 0: evidence; unit 1: evidence; unit 1: evidence; plan count 1, expected 2; : missing structured timing dans neuf jours; missing followUp: |
| 7B | Linked | negation-en | True | False |  |
| 7B | Linked + coverage | negation-en | True | False |  |
| 7B | Linked | negation-fr | False | False | ramipril: missing structured condition sauf si la clinique vous appelle |
| 7B | Linked + coverage | negation-fr | False | False | ramipril: missing structured condition sauf si la clinique vous appelle |
| 7B | Linked | approval-en | False | False | metformin: missing structured condition only after your pharmacist confirms the change; metformin: missing structured timing with breakfast; metformin: scope affirmed, expected conditional |
| 7B | Linked + coverage | approval-en | False | False | metformin: missing structured condition only after your pharmacist confirms the change; metformin: missing structured timing with breakfast; metformin: scope affirmed, expected conditional |
| 7B | Linked | approval-fr | False | False | metformine: missing structured condition seulement après confirmation du changement par votre pharmacien; metformine: scope affirmed, expected conditional |
| 7B | Linked + coverage | approval-fr | False | False | metformine: missing structured condition seulement après confirmation du changement par votre pharmacien; metformine: scope affirmed, expected conditional |
| 7B | Linked | alternating-en | True | False |  |
| 7B | Linked + coverage | alternating-en | True | False |  |
| 7B | Linked | alternating-fr | True | False |  |
| 7B | Linked + coverage | alternating-fr | True | False |  |
| 7B | Linked | empty-en | False | True | link: grouping |
| 7B | Linked + coverage | empty-en | False | True | link: grouping |
| 7B | Linked | empty-fr | False | True | link: grouping |
| 7B | Linked + coverage | empty-fr | False | True | link: grouping |
| Apple | One pass/native schema | switch-en | False |  | plan count 0, expected 2; missing medication:naproxen; missing medication:acetaminophen; invalidSequence |
| Apple | One pass/native schema | switch-fr | False |  | plan count 0, expected 2; missing medication:naproxène; missing medication:acétaminophène; invalidSequence |
| Apple | One pass/native schema | taper-en | False |  | plan count 0, expected 1; missing medication:prednisone; invalidSequence |
| Apple | One pass/native schema | taper-fr | False |  | plan count 0, expected 1; missing medication:prednisone; unsupportedEvidence |
| Apple | One pass/native schema | conditional-course-en | False |  | plan count 0, expected 1; missing medication:insulin; invalidSequence |
| Apple | One pass/native schema | conditional-course-fr | False |  | plan count 0, expected 1; missing medication:insuline; invalidSequence |
| Apple | One pass/native schema | followups-en | False |  | plan count 0, expected 2; missing followUp:; missing followUp:; invalidSequence |
| Apple | One pass/native schema | followups-fr | False |  | plan count 0, expected 2; missing followUp:; missing followUp:; invalidSequence |
| Apple | One pass/native schema | negation-en | False |  | plan count 0, expected 1; missing medication:ramipril; invalidSequence |
| Apple | One pass/native schema | negation-fr | False |  | plan count 0, expected 1; missing medication:ramipril; unsupportedEvidence |
| Apple | One pass/native schema | approval-en | False |  | plan count 0, expected 1; missing medication:metformin; invalidSequence |
| Apple | One pass/native schema | approval-fr | False |  | plan count 0, expected 1; missing medication:metformine; invalidSequence |
| Apple | One pass/native schema | alternating-en | False |  | plan count 0, expected 1; missing medication:warfarin; invalidSequence |
| Apple | One pass/native schema | alternating-fr | False |  | plan count 0, expected 1; missing medication:warfarine; invalidSequence |
| Apple | One pass/native schema | empty-en | False |  | unsupportedEvidence |
| Apple | One pass/native schema | empty-fr | False |  | unsupportedEvidence |
