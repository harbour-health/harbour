#!/usr/bin/env python3
"""Freeze and run one-pass versus linked extraction, with an additive coverage ablation."""
import argparse
import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(8 * 1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, action='append', required=True)
    parser.add_argument('--dataset', type=Path, default=ROOT / 'docs/evaluation/linked-plan-study/dataset.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evaluation/linked-plan-study/comparison')
    parser.add_argument('--executable', type=Path, default=ROOT / 'HarbourRuntime/.build/release/model-probe')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = sorted(list((ROOT / 'HarbourCore/Sources').rglob('*.swift')) + list((ROOT / 'HarbourRuntime/Sources').rglob('*.swift')))
    protocol = {
        'frozenAtUTC': datetime.now(timezone.utc).isoformat(),
        'datasetSHA256': digest(args.dataset), 'executableSHA256': digest(args.executable),
        'sources': {str(path.relative_to(ROOT)): digest(path) for path in sources},
        'runnerSHA256': digest(Path(__file__)),
        'sampling': 'greedy, seed 42, 4096 context; no tuning after outputs',
        'variants': ['one-pass typed plans', 'per-unit extraction + linking', 'same initial extraction + additive coverage + linking'],
        'coverageComparison': 'Reuse initial extraction outputs; coverage duration/calls include the initial linked stage. Review flags are not correctness passes.',
        'limits': 'Authored paired bilingual cases, not blinded clinical data or physical-phone benchmarks. One-pass scoring checks fields, not just JSON validity. No expected labels enter inference.',
        'experimentalPromotionGate': {
            'gain': 'at least 3 additional complete cases out of 16 versus one-pass on each tested model',
            'languages': 'at least 6/8 complete cases in each language',
            'regressions': 'no new failure on empty controls or conditional/negation cases',
            'extraPlans': 'no plan-count excess on any case',
            'decision': 'Meeting this engineering gate only justifies further review; it does not authorize medication writes or establish clinical accuracy.'
        },
        'models': []
    }
    for model in args.model:
        model = model.resolve()
        shards = sorted(model.parent.glob(model.name.replace('00001-of-00002', '*-of-00002'))) if '00001-of-00002' in model.name else [model]
        protocol['models'].append({'entry': model.name, 'shards': [{'name': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in shards]})
    with (args.output / 'protocol.json').open('x') as output:
        json.dump(protocol, output, indent=2); output.write('\n')
    (args.output / 'dataset.json').write_bytes(args.dataset.read_bytes())
    for mode in ['instructions', 'linked']:
        assert digest(args.executable) == protocol['executableSHA256'], 'Executable changed after freeze'
        command = ['python3', str(ROOT / 'scripts/evaluate-text-models.py'), '--mode', mode, '--dataset', str(args.dataset.resolve()), '--output', str((args.output / mode).resolve()), '--executable', str(args.executable.resolve())]
        for model in args.model: command += ['--model', str(model.resolve())]
        if mode == 'linked': command += ['--audit']
        subprocess.run(command, cwd=ROOT, check=True)
    print('Comparison finished. Review raw results and gates before changing the app.', flush=True)

if __name__ == '__main__': main()
