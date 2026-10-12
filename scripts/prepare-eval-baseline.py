#!/usr/bin/env python3
"""Prepare a fresh preserved e8028af Core workspace for the native model evaluator.

The output keeps the current runtime/evaluator and frozen fixture, while exporting
the original Core prompt builders and validators plus a reviewed API adapter.
Run its evaluate-models.py with --baseline-prompts to preserve grammar policy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parent.parent
BASELINE = "e8028afd7a27e3238835de818408b3c11d8747a5"

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1_048_576), b""):
            value.update(data)
    return value.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_directory.resolve()
    if output == ROOT or ROOT.is_relative_to(output) or output.is_relative_to(ROOT / "HarbourRuntime"):
        parser.error("Use a new workspace directory outside HarbourRuntime, not the repository or its parent.")
    adapter = ROOT / "evaluation/baseline/ModelPrompts.swift"
    adapter_metadata = json.loads((adapter.with_suffix(".json")).read_text(encoding="utf-8"))
    if digest(adapter) != adapter_metadata["adapter_sha256"]:
        parser.error("The preserved baseline adapter failed its SHA-256 check.")
    source = subprocess.check_output(["git", "show", f"{BASELINE}:Harbour/ModelManager.swift"], cwd=ROOT)
    if hashlib.sha256(source).hexdigest() != adapter_metadata["original_app_source_sha256"]:
        parser.error("The preserved app source failed its SHA-256 check.")
    output.mkdir(parents=True, exist_ok=False)
    archive = output / "baseline-core.tar"
    subprocess.run(["git", "archive", "--format=tar", "--output", str(archive), BASELINE, "HarbourCore"], cwd=ROOT, check=True)
    with tarfile.open(archive) as package:
        for member in package.getmembers():
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or member.issym() or member.islnk():
                raise RuntimeError(f"Unsafe baseline archive path: {member.name}")
        package.extractall(output, filter="data")
    original_core = {str(path.relative_to(output)): digest(path)
        for path in sorted((output / "HarbourCore").rglob("*")) if path.is_file()}
    shutil.copytree(ROOT / "HarbourRuntime", output / "HarbourRuntime",
        ignore=shutil.ignore_patterns(".build", "Vendor", ".swiftpm", "__pycache__"))
    paths = ["scripts/evaluate-models.py", "scripts/prepare-linux-runtime.py", "scripts/cache-eval-models.py",
        "scripts/prepare-eval-baseline.py", "scripts/model-eval/Dockerfile", "evaluation/harbour-model-quality-v1.json",
        "evaluation/score.py", "evaluation/baseline/ModelPrompts.swift", "evaluation/baseline/ModelPrompts.json"]
    for relative in paths:
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, destination)
    shutil.copy2(adapter, output / "HarbourCore/Sources/HarbourCore/ModelPrompts.swift")
    shutil.copy2(adapter.with_suffix(".json"), output / "baseline-adapter.json")
    overlay = {str(path.relative_to(output)): digest(path) for path in sorted(output.rglob("*"))
        if path.is_file() and path != archive and str(path.relative_to(output)) not in original_core}
    metadata = {"formatVersion": 1, "baselineCommit": BASELINE, "coreArchiveSHA256": digest(archive),
        "originalCoreSHA256": original_core, "overlaySHA256": overlay, "adapter": adapter_metadata,
        "scope": "Original Core prompts and validators; current LocalModel/runtime and evaluation adapter; original grammar policy via --baseline-prompts."}
    (output / "baseline-workspace.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(output)

if __name__ == "__main__":
    main()
