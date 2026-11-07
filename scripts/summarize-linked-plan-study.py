#!/usr/bin/env python3
"""Summarize frozen outputs without running inference or changing grades."""
import argparse
import json
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def cell(value):
    return str(value).replace('|', '\\|').replace('\n', ' ')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', type=Path, default=ROOT / 'docs/evaluation/linked-plan-study')
    args = parser.parse_args(); base = args.study
    comparison = base / 'comparison'; protocol = json.loads((comparison / 'protocol.json').read_text())
    groups = {}; case_rows = []; flags = []
    for folder, variant in [('instructions', 'One pass'), ('linked', None)]:
        for file in sorted((comparison / folder).glob('*-results.json')):
            report = json.loads(file.read_text()); model = '7B' if '7b-' in report['model'] else '1.5B'
            for run in report['runs']:
                name = variant or ('Linked + coverage' if run['effort'] == 'coverage' else 'Linked')
                groups.setdefault((model, name), []).append(run)
                case_rows.append((model, name, run['id'], run['passed'], run.get('needsReview', ''), '; '.join(run['failures'] + ([run['error']] if run.get('error') else []))))
    text = ['# Linked-plan study results', '', 'These are strict synthetic text-fixture results, not clinical accuracy or iPhone performance. All candidate prompts and expected fields were frozen before candidate inference. Paired French/English cases are related examples.', '', '## Unchanged focused summary baseline', '', '| Model | Complete cases /20 |', '| --- | ---: |']
    for model, path in [('1.5B', ROOT / 'docs/evaluation/focused-holdout/qwen2.5-1.5b-instruct-q4_k_m-results.json'), ('3B', ROOT / 'docs/evaluation/focused-holdout/qwen2.5-3b-instruct-q4_k_m-results.json'), ('7B', next((base / '7b-baseline').glob('*-results.json')))]:
        runs = json.loads(path.read_text())['runs']; text.append(f'| {model} | {sum(r["passed"] for r in runs)}/{len(runs)} |')
    text += ['', 'The original summary contract and the new typed-plan contract differ. Their percentages must not be treated as one comparable accuracy scale.', '', '## New bilingual comparison', '', '| Model | Variant | Complete /16 | English /8 | French /8 | Valid output /16 | Review flags | Median seconds |', '| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for model in ['1.5B', '7B']:
        for variant in ['One pass', 'Linked', 'Linked + coverage']:
            runs = groups[(model, variant)]
            counts = [sum(r['passed'] for r in runs)] + [sum(r['passed'] for r in runs if r['language'] == lang) for lang in ['en', 'fr']]
            text.append(f'| {model} | {variant} | {counts[0]}/{len(runs)} | {counts[1]}/8 | {counts[2]}/8 | {sum(r["valid"] for r in runs)}/{len(runs)} | {sum(r.get("needsReview",False) for r in runs)} | {statistics.median(r["seconds"] for r in runs):.1f} |')
    text += ['', 'Coverage reuses the linked first-pass generations. Its timing includes initial extraction and linking; it is not a separately timed rerun. Valid output means the parser/evidence checks passed, which does not establish semantic correctness.', '', '## Preregistered engineering gates', '', '| Model | Candidate | Gain ≥3 cases | ≥6/8 each language | No new control/scope failure | No excess plans | Gate |', '| --- | --- | --- | --- | --- | --- | --- |']
    for model in ['1.5B', '7B']:
        reference = {r['id']: r for r in groups[(model, 'One pass')]}
        for variant in ['Linked', 'Linked + coverage']:
            runs = groups[(model, variant)]
            gain = sum(r['passed'] for r in runs) - sum(r['passed'] for r in reference.values()) >= 3
            languages = all(sum(r['passed'] for r in runs if r['language'] == lang) >= 6 for lang in ['en', 'fr'])
            controls = all(not reference[r['id']]['passed'] or r['passed'] for r in runs if r['id'].startswith(('empty-', 'negation-', 'approval-', 'conditional-course-')))
            expected = {c['id']: len(c['expected']) for c in json.loads((comparison / 'dataset.json').read_text())['cases']}
            extras = all(len(r['plans']) <= expected[r['id']] for r in runs)
            checks = [gain, languages, controls, extras]; flags.append(all(checks))
            text.append('| ' + ' | '.join([model, variant] + ['Pass' if v else 'Fail' for v in checks] + ['Pass' if all(checks) else 'Fail']) + ' |')
    text += ['', 'No failed experiment should replace the active extractor. An engineering gate pass supports further review only, not medication writes or a clinical accuracy claim.', '', '## Review-flag performance', '', '| Model | Variant | Failed cases flagged | Passing cases flagged |', '| --- | --- | ---: | ---: |']
    for (model, variant), runs in groups.items():
        if variant == 'One pass': continue
        failed = [r for r in runs if not r['passed']]; passed = [r for r in runs if r['passed']]
        text.append(f'| {model} | {variant} | {sum(r["needsReview"] for r in failed)}/{len(failed)} | {sum(r["needsReview"] for r in passed)}/{len(passed)} |')
    text += ['', 'A model concern or validator rejection is only a review signal. Unflagged failed cases show why this signal cannot guarantee completeness.', '', 'See [all candidate cases](case-matrix.md), [protocol](comparison/protocol.json), [dataset](comparison/dataset.json) and raw outputs under `comparison/`. The 7B frozen-baseline first launch failed because the copied executable lacked its adjacent framework; `7b-launch-failure/` preserves that error. The completed baseline followed after restoring the existing dependency. No failed launch is counted as an inference result.', '', 'Rebuild this report with `python3 scripts/summarize-linked-plan-study.py`. No grades are changed.']
    apple = base / 'apple/apple-results.json'
    if apple.exists():
        report = json.loads(apple.read_text()); runs = report['runs']
        text += ['', '## Apple on-device system model', '', '| Backend | Contract passes | English | French | Parser/evidence valid | Errors or validation failures |', '| --- | ---: | ---: | ---: | ---: | ---: |',
            f'| SystemLanguageModel.default | {sum(r["passed"] for r in runs)}/{len(runs)} | {sum(r["passed"] for r in runs if r["language"] == "en")}/8 | {sum(r["passed"] for r in runs if r["language"] == "fr")}/8 | {sum(r["valid"] for r in runs)}/{len(runs)} | {sum(r.get("error") is not None for r in runs)} |', '',
            'This is the one-pass typed-plan task with native `@Generable` output and default guardrails, not the focused-summary baseline or the linked pipeline. Apple adds its own system instructions and schema. Its OS-managed model is not pinned to a GGUF checksum. Refusals, API errors and local evidence/sequence validation failures all count as failures; raw errors distinguish them. No safeguard bypass or retries were used. See [Apple manifest](apple/manifest.json) and [raw outputs](apple/apple-results.json). This initial generic adapter is not a conclusion about the best achievable quality with an Apple-specific prompt/schema.']
        for r in runs:
            case_rows.append(('Apple', 'One pass/native schema', r['id'], r['passed'], '', '; '.join(r['failures'] + ([r['error']] if r.get('error') else []))))
    (base / 'results.md').write_text('\n'.join(text) + '\n')
    matrix = ['# Candidate case matrix', '', '| Model | Variant | Case | Pass | Review flag | Failures |', '| --- | --- | --- | --- | --- | --- |']
    matrix += ['| ' + ' | '.join(cell(v) for v in row) + ' |' for row in case_rows]
    (base / 'case-matrix.md').write_text('\n'.join(matrix) + '\n')
    print('\n'.join(text[:32]))

if __name__ == '__main__': main()
