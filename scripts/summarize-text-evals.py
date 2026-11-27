#!/usr/bin/env python3
"""Render the frozen text-evaluation matrix without rerunning or regrading outputs."""
import csv
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'docs/evaluation'
models = ['qwen2.5-0.5b-instruct-q4_k_m', 'qwen2.5-1.5b-instruct-q4_k_m', 'qwen2.5-3b-instruct-q4_k_m']
groups = [
    ('Routing', '.', 'routing', 'Standard', '-routing-corrected.json'),
    ('Conversation', '.', 'conversation', 'Standard', '-results.json'),
    ('Tool narration · development', 'narration-development', 'tool-result', 'Standard', '-results.json'),
    ('Tool narration · holdout', 'narration-holdout', 'tool-result', 'Standard', '-results.json'),
    ('Titles', 'chat-titles', 'titles', 'fixed', '-results.json'),
    ('Visit summary · development', 'focused-development-round2', 'medical', 'focused', '-results.json'),
    ('Visit summary · holdout', 'focused-holdout', 'medical', 'focused', '-results.json'),
]
summary, cases = [], []
for label, folder, category, effort, suffix in groups:
    row = {'Task': label}
    by_name = {}
    for model in models:
        report = json.loads((root / folder / (model + suffix)).read_text())
        runs = [r for r in report['runs'] if r['category'] == category and r['effort'] == effort]
        row[model] = f"{sum(bool(r['passed']) for r in runs)}/{len(runs)}"
        for run in runs:
            by_name.setdefault(run['name'], {'Task': label, 'Case': run['name']})[model] = 'PASS' if run['passed'] else 'FAIL'
    summary.append(row)
    cases.extend(by_name.values())

for filename, rows in [('results.csv', summary), ('case-matrix.csv', cases)]:
    with (root / filename).open('w') as output:
        writer = csv.DictWriter(output, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

def table(rows, keys):
    headings = ['Task', '0.5B', '1.5B', '3B'] if keys[0] == 'Task' else ['Case', '0.5B', '1.5B', '3B']
    return '\n'.join(['| ' + ' | '.join(headings) + ' |', '| --- | ---: | ---: | ---: |'] + [
        '| ' + ' | '.join(str(r.get(k, 'Not tested')).replace('|', '\\|').replace('\n', ' ') for k in keys) + ' |' for r in rows
    ])

(root / 'matrix.md').write_text('# Text model matrix\n\n' + table(summary, ['Task'] + models) + '\n\n'
    'Counts are engineering-case agreement, not clinical accuracy. The primary chat rows use Standard effort and greedy sampling. '
    'Summary rows use focused model passes with source validation and no missing-fact recovery. '
    'See [results and limitations](results.md) for effort, temperature, fact counts and provenance.\n')
parts = ['# Per-case text matrix', 'Original automatic grades are retained. These are screening checks, not expert-reviewed medical judgments. The corresponding JSON files contain the actual outputs and source facts.']
for label, *_ in groups:
    parts += ['## ' + label, table([r for r in cases if r['Task'] == label], ['Case'] + models)]
(root / 'case-matrix.md').write_text('\n\n'.join(parts) + '\n')
print(f'Wrote {len(summary)} task rows and {len(cases)} per-case rows.')
