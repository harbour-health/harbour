#!/usr/bin/env python3
"""Run reproducible, text-only model probes; never deletes model files."""
import argparse
import hashlib
import json
import math
import platform
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(8 * 1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()

def summarize(report):
    groups = {}
    for run in report['runs']:
        group = groups.setdefault(run.get('category', 'instructions') + '/' + run.get('effort', run.get('language', 'standard')), {'passed': 0, 'total': 0, 'errors': 0, 'seconds': 0})
        group['passed'] += run['passed']; group['total'] += 1
        group['errors'] += bool(run.get('error')); group['seconds'] += run['seconds']
        if run.get('category') == 'medical':
            for stage in ['rawFacts', 'validatedFacts', 'completedFacts']:
                expected = set(run.get('expectedCompletedFacts', run['expectedFacts']) if stage != 'rawFacts' else run['expectedFacts'])
                actual = set(run[stage])
                counts = group.setdefault(stage, {'correctFacts': 0, 'expectedFacts': 0, 'extraFacts': 0, 'exactCases': 0})
                counts['correctFacts'] += len(expected & actual); counts['expectedFacts'] += len(expected)
                counts['extraFacts'] += len(actual - expected); counts['exactCases'] += actual == expected
    return groups

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, action='append', required=True)
    parser.add_argument('--mode', choices=['text', 'focused', 'narration', 'titles', 'instructions'], default='text')
    parser.add_argument('--dataset', type=Path, default=ROOT / 'docs/evaluation/text-suite-v1.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evaluation')
    parser.add_argument('--audit', action='store_true', help='Experimental model audit after focused extraction')
    parser.add_argument('--temperature', type=float, default=0)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--executable', type=Path, default=ROOT / 'HarbourRuntime/.build/release/model-probe')
    args = parser.parse_args()
    if not math.isfinite(args.temperature) or not 0 <= args.temperature <= 2: parser.error('temperature must be finite and between 0 and 2')
    if not 0 <= args.seed <= 4294967295: parser.error('seed must fit an unsigned 32-bit integer')
    if args.mode in ['text', 'titles'] and args.temperature != 0: parser.error('temperature experiments use focused or narration mode')
    if args.audit and args.mode != 'focused': parser.error('--audit requires --mode focused')
    args.output.mkdir(parents=True, exist_ok=True)
    sources = ['HarbourCore/Sources/HarbourCore/ToolPlanner.swift', 'HarbourCore/Sources/HarbourCore/Visits.swift', 'HarbourCore/Sources/HarbourCore/VisitDirections.swift', 'HarbourCore/Sources/HarbourCore/VisitExtraction.swift', 'HarbourCore/Sources/HarbourCore/ChatTitles.swift', 'HarbourRuntime/Sources/ModelProbe/TextEvaluation.swift', 'HarbourRuntime/Sources/ModelProbe/LegacySourceRecovery.swift', 'HarbourRuntime/Sources/ModelProbe/BaselineVisitPrompt.swift', 'HarbourRuntime/Sources/ModelProbe/BaselineVisitGrammar.swift', 'HarbourRuntime/Sources/HarbourRuntime/VisitSummaryOutputGrammar.swift', 'HarbourRuntime/Sources/HarbourRuntime/LocalModel.swift']
    if (ROOT / 'HarbourRuntime/Sources/ModelProbe/VisitAuditExperiment.swift').exists(): sources.append('HarbourRuntime/Sources/ModelProbe/VisitAuditExperiment.swift')
    if args.mode == 'instructions':
        sources += ['HarbourCore/Sources/HarbourCore/InstructionPlans.swift', 'HarbourRuntime/Sources/ModelProbe/InstructionEvaluation.swift']
    snapshot = args.output / 'prompt-snapshot'; snapshot.mkdir(exist_ok=True)
    executable_hash = digest(args.executable)
    frozen = None
    for candidate in sorted((ROOT / 'docs/evaluation').rglob('manifest.json')):
        try:
            archived = json.loads(candidate.read_text())
            if archived.get('executableSHA256') == executable_hash and all((candidate.parent / 'prompt-snapshot' / Path(name).name).exists() and digest(candidate.parent / 'prompt-snapshot' / Path(name).name) == checksum for name, checksum in archived['sourceSHA256'].items()):
                frozen = (candidate.parent, archived['sourceSHA256']); break
        except (KeyError, ValueError, OSError): pass
    hashes = {}
    if frozen:
        origin, hashes = frozen
        for name in hashes: (snapshot / Path(name).name).write_bytes((origin / 'prompt-snapshot' / Path(name).name).read_bytes())
    else:
        extra = ROOT / 'HarbourRuntime/Sources/HarbourRuntime/ModelSampling.swift'
        if extra.exists(): sources.append(str(extra.relative_to(ROOT)))
        for name in sources:
            path = ROOT / name; hashes[name] = digest(path); (snapshot / path.name).write_bytes(path.read_bytes())
    manifest = {'mode': args.mode, 'audit': args.audit, 'temperature': args.temperature, 'seed': args.seed, 'runnerSHA256': digest(Path(__file__)), 'host': platform.platform(), 'datasetSHA256': digest(args.dataset), 'executableSHA256': executable_hash, 'sourceSHA256': hashes, 'sourceSnapshotOrigin': str(frozen[0].relative_to(ROOT)) if frozen else 'current source at build freeze', 'models': []}
    for model in args.model:
        model = model.resolve(); destination = args.output / (model.stem + '-results.json')
        if digest(args.executable) != manifest['executableSHA256']: raise RuntimeError('Evaluation executable changed during the comparison; use one fixed build per run.')
        entry = {'file': model.name, 'bytes': model.stat().st_size, 'sha256': digest(model)}
        print('Running', model.name, flush=True)
        with (args.output / (model.stem + '.log')).open('w') as log:
            process = subprocess.run([str(args.executable), str(model), '--' + args.mode + '-suite', '--dataset', str(args.dataset.resolve()), '--output', str(destination.resolve()), '--temperature', str(args.temperature), '--seed', str(args.seed)] + (['--audit'] if args.audit else []), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        entry['exitCode'] = process.returncode
        if destination.exists(): entry['summary'] = summarize(json.loads(destination.read_text()))
        manifest['models'].append(entry)
        (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        print('Finished', model.name, process.returncode, flush=True)
        if process.returncode: raise SystemExit(process.returncode)

if __name__ == '__main__': main()
