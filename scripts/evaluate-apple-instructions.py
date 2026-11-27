#!/usr/bin/env python3
"""Evaluate Apple's local system model with the shared typed-plan task and scorer."""
import argparse
import hashlib
import json
import platform
import subprocess
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', type=Path, default=ROOT / 'docs/evaluation/linked-plan-study/dataset.json')
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/evaluation/linked-plan-study/apple')
    parser.add_argument('--executable', type=Path, default=ROOT / 'HarbourRuntime/.build/release/model-probe')
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    names = ['HarbourCore/Sources/HarbourCore/InstructionPlans.swift', 'HarbourRuntime/Sources/ModelProbe/InstructionEvaluation.swift', 'HarbourRuntime/Sources/ModelProbe/AppleInstructionEvaluation.swift']
    sources = args.output / 'prompt-snapshot'; sources.mkdir(exist_ok=True)
    for name in names: (sources / Path(name).name).write_bytes((ROOT / name).read_bytes())
    manifest = dict(startedAtUTC=datetime.now(timezone.utc).isoformat(), host=platform.platform(),
        provider='SystemLanguageModel.default; on-device only; default guardrails; native guided generation',
        modelVersion='OS managed; framework does not expose a pinned weight hash in this probe',
        datasetSHA256=digest(args.dataset), executableSHA256=digest(args.executable), runnerSHA256=digest(Path(__file__)),
        sourceSHA256={name: digest(ROOT / name) for name in names})
    with (args.output / 'manifest.json').open('x') as output: json.dump(manifest, output, indent=2); output.write('\n')
    (args.output / 'dataset.json').write_bytes(args.dataset.read_bytes())
    with (args.output / 'apple.log').open('w') as log:
        result = subprocess.run([str(args.executable.resolve()), 'apple', '--apple-instructions-suite', '--dataset', str(args.dataset.resolve()), '--output', str((args.output / 'apple-results.json').resolve())], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    manifest['exitCode'] = result.returncode
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    if result.returncode: raise SystemExit(result.returncode)
    runs = json.loads((args.output / 'apple-results.json').read_text())['runs']
    print(f'Apple: {sum(r["passed"] for r in runs)}/{len(runs)} full cases; {sum(r.get("error") is not None for r in runs)} errors/validation failures', flush=True)

if __name__ == '__main__': main()
