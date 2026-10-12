#!/usr/bin/env python3
"""Run controlled model comparisons through the production Swift LocalModel actor.

Run on Linux inside scripts/model-eval/Dockerfile. The output directory must be
new, so previous before/after evidence cannot be overwritten accidentally.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1_048_576), b""):
            value.update(data)
    return value.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, default=ROOT / "evaluation/harbour-model-quality-v1.json")
    parser.add_argument("--models-directory", type=Path, required=True)
    parser.add_argument("--models", nargs="+", choices=["small", "balanced", "qwen35"], default=["small", "balanced", "qwen35"])
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--runtime-prefix", type=Path, default=ROOT / "build/runtime/linux-b10549")
    parser.add_argument("--efforts", default="standard", help="Comma-separated quick,standard,extended.")
    parser.add_argument("--repeats", type=int, choices=range(1, 6), default=1)
    parser.add_argument("--split", choices=["all", "dev", "heldout"], default="all")
    parser.add_argument("--ids", help="Comma-separated case IDs, useful for the preserved tuning subset.")
    parser.add_argument("--baseline-prompts", action="store_true")
    parser.add_argument("--context-checks", action="store_true")
    parser.add_argument("--grammar-checks", action="store_true")
    parser.add_argument("--diagnostics-only", action="store_true", help="Run only requested native grammar/context checks, without quality fixture inference.")
    parser.add_argument("--source-label", default="current-source", help="Report label, e.g. baseline-e8028af or final-PR.")
    args = parser.parse_args()
    if len(set(args.models)) != len(args.models):
        parser.error("Each model must be selected at most once.")
    if args.baseline_prompts != (ROOT / "baseline-adapter.json").is_file():
        parser.error("Use --baseline-prompts only in the preserved workspace from prepare-eval-baseline.py; that workspace requires the flag.")
    if args.diagnostics_only and not (args.grammar_checks or args.context_checks):
        parser.error("--diagnostics-only requires --grammar-checks or --context-checks.")
    if sys.platform != "linux":
        parser.error("Run the native CPU comparison on Linux or with scripts/model-eval/Dockerfile.")
    suite = args.suite.resolve()
    if not suite.is_file():
        parser.error(f"Missing evaluation suite: {suite}")
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    models = args.models_directory.resolve()
    prefix = args.runtime_prefix.resolve()
    subprocess.run([sys.executable, str(ROOT / "scripts/cache-eval-models.py"), "--directory", str(models), "--models", *args.models], check=True)
    subprocess.run([sys.executable, str(ROOT / "scripts/prepare-linux-runtime.py"), "--prefix", str(prefix)], check=True)
    environment = dict(os.environ, HARBOUR_LINUX_RUNTIME="1", HARBOUR_DEVICE_RUNTIME="0", SWIFT_DETERMINISTIC_HASHING="1")
    environment.pop("SDKROOT", None)
    environment["PKG_CONFIG_PATH"] = str(prefix / "lib/pkgconfig") + (":" + environment["PKG_CONFIG_PATH"] if environment.get("PKG_CONFIG_PATH") else "")
    environment["LD_LIBRARY_PATH"] = str(prefix / "lib") + (":" + environment["LD_LIBRARY_PATH"] if environment.get("LD_LIBRARY_PATH") else "")
    build = ["swift", "build", "--package-path", str(ROOT / "HarbourRuntime"), "--configuration", "release", "--product", "model-eval", "--jobs", "4"]
    subprocess.run(build, env=environment, check=True)
    bin_path = subprocess.check_output(["swift", "build", "--package-path", str(ROOT / "HarbourRuntime"), "--configuration", "release", "--show-bin-path"], env=environment, text=True).strip()
    executable = Path(bin_path) / "model-eval"
    source_paths = sorted({"HarbourRuntime/Package.swift", "HarbourCore/Package.swift",
        "scripts/evaluate-models.py", "scripts/prepare-linux-runtime.py", "scripts/cache-eval-models.py",
        "scripts/model-eval/Dockerfile"} | {name for name in ["baseline-adapter.json", "baseline-workspace.json"] if (ROOT / name).is_file()} | {
        str(path.relative_to(ROOT)) for directory in [ROOT / "HarbourCore/Sources", ROOT / "HarbourRuntime/Sources"]
        for path in directory.rglob("*") if path.is_file() and path.suffix in {".swift", ".h", ".modulemap"}})
    specifications = json.loads((models / "model-provenance.json").read_text())
    metadata = {"formatVersion": 1, "startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "complete": False, "sourceLabel": args.source_label, "platform": platform.platform(), "processor": platform.processor(), "logicalProcessors": os.cpu_count(),
        "swiftVersion": subprocess.check_output(["swift", "--version"], text=True).strip(),
        "runtime": json.loads((prefix / "harbour-runtime.json").read_text()),
        "runtimeFilesSHA256": {str(path.relative_to(prefix)): digest(path) for path in sorted(prefix.rglob("*")) if path.is_file()},
        "models": specifications,
        "suite": str(suite), "suiteSHA256": digest(suite), "executableSHA256": digest(executable),
        "sourceSHA256": {path: digest(ROOT / path) for path in source_paths},
        "settings": {"context": 4096, "batch": 512, "threads": "min(4, processorCount-2), at least1",
            "backend": "Linux CPU", "sampling": "production grammar sampler followed by greedy", "JSONStopping": "production JSONEnvelope",
            "efforts": args.efforts, "repeats": args.repeats, "repeatScope": "standard effort timingSubset only", "split": args.split,
            "tokenBudgets": {"routing": {"quick": 96, "standard": 160, "extended": 256}, "reply": {"quick": 256, "standard": 512, "extended": 768}, "title": {"en": 48, "fr-CA": 96}, "visit": 650},
            "grammarPolicy": {"routing": "19-tool empty-argument grammar", "prose": "none", "title": "French only" if args.baseline_prompts else "both languages", "visit": "none" if args.baseline_prompts else "source-grounded quote/action alternatives and bounded count"},
            "ids": args.ids, "baselinePrompts": args.baseline_prompts, "contextChecks": args.context_checks, "grammarChecks": args.grammar_checks, "diagnosticsOnly": args.diagnostics_only},
        "commands": [], "promptSHA256": {}, "limits": "Production native CPU path; no physical iPhone/Metal or clinical validation."}
    metadata_file = output / "metadata.json"
    metadata_file.write_text(json.dumps(metadata, indent=2) + "\n")
    try:
        for name in args.models:
            spec = next(value for value in specifications if value["model"] == name)
            command = [str(executable), "--model", str(models / spec["filename"]), "--model-id", name,
                "--suite", str(suite), "--output", str(output / f"{name}.jsonl"), "--efforts", args.efforts,
                "--repeats", str(args.repeats), "--split", args.split]
            if args.ids: command += ["--ids", args.ids]
            if args.baseline_prompts: command += ["--baseline-prompts"]
            if args.context_checks: command += ["--context-checks"]
            if args.grammar_checks: command += ["--grammar-checks"]
            if args.diagnostics_only: command += ["--diagnostics-only"]
            metadata["commands"].append(command)
            metadata_file.write_text(json.dumps(metadata, indent=2) + "\n")
            print(f"Evaluating {name} sequentially through production Swift runtime", flush=True)
            with (output / f"{name}.stdout.json").open("w") as stdout, (output / f"{name}.stderr.log").open("w") as log:
                process = subprocess.Popen(command, env=environment, stdout=stdout, stderr=subprocess.PIPE, text=True)
                for line in process.stderr:
                    log.write(line); log.flush()
                    if line.startswith(name + " "): print(line.rstrip(), flush=True)
                return_code = process.wait()
            if return_code:
                tail = (output / f"{name}.stderr.log").read_text(errors="replace")[-5000:]
                raise RuntimeError(f"Native evaluator failed for {name}, exit {return_code}:\n{tail}")
            rows = [json.loads(line) for line in (output / f"{name}.jsonl").read_text().splitlines() if line]
            metadata["promptSHA256"][name] = [{"caseID": row["caseID"], "effort": row["effort"], "repeatIndex": row["repeatIndex"],
                "prompt": hashlib.sha256(row["prompt"].encode()).hexdigest(),
                "replyPrompt": hashlib.sha256(row["replyPrompt"].encode()).hexdigest() if row.get("replyPrompt") else None}
                for row in rows if row.get("prompt")]
            metadata.setdefault("responseGrammarSHA256", {})[name] = [{"caseID": row["caseID"], "effort": row["effort"], "repeatIndex": row["repeatIndex"],
                "sha256": hashlib.sha256(row["responseGrammar"].encode()).hexdigest() if row.get("responseGrammar") else None} for row in rows]
        metadata["complete"] = True
    finally:
        metadata["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        metadata_file.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Complete raw model evidence: {output}", flush=True)

if __name__ == "__main__":
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Model comparison failed: {error}")
