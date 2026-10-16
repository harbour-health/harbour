#!/usr/bin/env python3
"""Run the production model-probe catalog sequentially and preserve raw evidence.

This supplemental suite comes from HarbourCore.Evaluation, independently of the
frozen comparative fixture. Validation is read-only; no app records are executed.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from visit_stage_evidence import bind_visit_stages

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1_048_576), b""):
            value.update(data)
    return value.hexdigest()


def text_digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def summarize(rows, stdout, exit_code):
    routing = re.findall(r"^(\d+)/(\d+) model routing cases passed$", stdout, re.MULTILINE)
    visits = re.findall(r"^(\d+)/(\d+) transcript cases passed$", stdout, re.MULTILINE)
    if exit_code not in {0, 1} or len(routing) != 1 or len(visits) != 1:
        raise RuntimeError("The native probe did not complete both production catalogs.")
    counters = {}
    for kind, matches in [("routing", routing), ("visit", visits)]:
        passed, total = map(int, matches[0])
        selected = [row for row in rows if row.get("kind") == kind]
        if not total or len(selected) != total or sum(row.get("fixtureMatched") is True for row in selected) != passed:
            raise RuntimeError(f"The {kind} report does not match the native completion summary.")
        counters[kind] = {"passed": passed, "total": total}
    if len(rows) != sum(counter["total"] for counter in counters.values()) or len({(row["kind"], row["caseID"]) for row in rows}) != len(rows):
        raise RuntimeError("Duplicate or unexpected native probe results.")
    all_passed = all(counter["passed"] == counter["total"] for counter in counters.values())
    if (exit_code == 0) != all_passed:
        raise RuntimeError("Native quality exit status disagrees with its report.")
    counters["fallbackVisits"] = sum(row.get("fallbackUsed") is True for row in rows if row["kind"] == "visit")
    visit_rows = [row for row in rows if row["kind"] == "visit"]
    counters["visitSemantic"] = {"passed": sum(row.get("semanticFixtureMatched", row["fixtureMatched"]) is True for row in visit_rows), "total": len(visit_rows)}
    counters["terminalPeriodOnlyDifferences"] = [row["caseID"] for row in visit_rows if row.get("semanticFixtureMatched") is True and row["fixtureMatched"] is False]
    counters["fixtureMedicineAndAppointmentRecallWithoutFallback"] = counters["visitSemantic"]["passed"] == len(visit_rows) and counters["fallbackVisits"] == 0
    counters["rejectedMedicineProposals"] = sum(row.get("rejectedMedicineProposals", 0) or 0 for row in rows)
    counters["acceptedUnexpectedTools"] = [row["caseID"] for row in rows if row["kind"] == "routing" and row.get("acceptedAction") and row["acceptedAction"]["type"] != row["expectedTool"]]
    counters["manualSourceAndSafetyReviewRequired"] = True
    return counters


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--models-directory", type=Path, required=True)
    parser.add_argument("--models", nargs="+", choices=["small", "balanced", "qwen35"], default=["qwen35", "small", "balanced"])
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--runtime-prefix", type=Path, required=True)
    parser.add_argument("--source-label", default="current-source")
    args = parser.parse_args()
    if sys.platform != "linux":
        parser.error("Run the native CPU suite on Linux or with scripts/model-eval/Dockerfile.")
    if len(set(args.models)) != len(args.models):
        parser.error("Each model must be selected at most once.")
    if (ROOT / "baseline-adapter.json").exists():
        parser.error("The supplemental suite requires the current production Core catalog.")
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=False)
    models, prefix = args.models_directory.resolve(), args.runtime_prefix.resolve()
    subprocess.run([sys.executable, str(ROOT / "scripts/cache-eval-models.py"), "--directory", str(models), "--models", *args.models], check=True)
    subprocess.run([sys.executable, str(ROOT / "scripts/prepare-linux-runtime.py"), "--prefix", str(prefix)], check=True)
    environment = dict(os.environ, HARBOUR_LINUX_RUNTIME="1", HARBOUR_DEVICE_RUNTIME="0", SWIFT_DETERMINISTIC_HASHING="1")
    environment.pop("SDKROOT", None)
    environment["PKG_CONFIG_PATH"] = str(prefix / "lib/pkgconfig") + (":" + environment["PKG_CONFIG_PATH"] if environment.get("PKG_CONFIG_PATH") else "")
    environment["LD_LIBRARY_PATH"] = str(prefix / "lib") + (":" + environment["LD_LIBRARY_PATH"] if environment.get("LD_LIBRARY_PATH") else "")
    subprocess.run(["swift", "build", "--package-path", str(ROOT / "HarbourRuntime"), "--configuration", "release", "--product", "model-probe", "--jobs", "4"], env=environment, check=True)
    bin_path = subprocess.check_output(["swift", "build", "--package-path", str(ROOT / "HarbourRuntime"), "--configuration", "release", "--show-bin-path"], env=environment, text=True).strip()
    executable = Path(bin_path) / "model-probe"
    sources = sorted({"HarbourRuntime/Package.swift", "HarbourCore/Package.swift", "scripts/evaluate-model-probe.py", "scripts/visit_stage_evidence.py", "scripts/prepare-linux-runtime.py", "scripts/cache-eval-models.py", "scripts/model-eval/Dockerfile"} | {
        str(path.relative_to(ROOT)) for directory in [ROOT / "HarbourCore/Sources", ROOT / "HarbourRuntime/Sources"]
        for path in directory.rglob("*") if path.is_file() and path.suffix in {".swift", ".h", ".modulemap"}})
    specifications = json.loads((models / "model-provenance.json").read_text())
    metadata = {"formatVersion": 1, "suite": "production Evaluation.routingCases and visitSummaryCases", "sourceLabel": args.source_label,
        "startedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(), "complete": False,
        "platform": platform.platform(), "processor": platform.processor(), "logicalProcessors": os.cpu_count(),
        "swiftVersion": subprocess.check_output(["swift", "--version"], text=True).strip(), "models": specifications,
        "runtime": json.loads((prefix / "harbour-runtime.json").read_text()),
        "runtimeFilesSHA256": {str(path.relative_to(prefix)): digest(path) for path in sorted(prefix.rglob("*")) if path.is_file()},
        "sourceSHA256": {path: digest(ROOT / path) for path in sources}, "executableSHA256": digest(executable),
        "settings": {"context": 4096, "batch": 512, "threads": "min(4, processorCount-2), at least1", "backend": "Linux CPU",
            "sampling": "production grammar sampler followed by greedy", "JSONStopping": "production JSONEnvelope",
            "tokenBudgets": {"routing": 160, "reply": 512, "visit": 650}, "repeats": 1, "modelsSequential": True,
            "language": "English app locale for routing/replies; French locale for French visit fixture",
            "grammarPolicy": "production available-tool grammar; all-source-unit classifier and unbound per-selected-unit visit extraction", "recordExecution": False,
            "visitBudgetScope": "650 per generation call; staged total is 650 times recorded calls, not equal-total-compute model IQ."},
        "commands": [], "summary": {}, "reportSHA256": {}, "stdoutSHA256": {}, "stderrSHA256": {}, "inputBindings": {}, "exitCodes": {},
        "qualityPolicy": "Exit1 is a completed legacy quality failure. Legacy fixture.matches verdict is preserved; semantic visit verdict permits only source-faithful nonempty instructions differing in terminal period. All other action/name/frequency/time/raw-recall guards remain unchanged. Raw recall, validator and fallback results remain separate; source safety requires review.",
        "limits": "Supplemental production catalog; no frozen-v1 appointment recall claim and no physical iPhone/Metal evaluation."}
    metadata_path = output / "metadata.json"
    def save():
        metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
    save()
    try:
        for name in args.models:
            spec = next(value for value in specifications if value["model"] == name)
            report, stdout_path, stderr_path = output / f"{name}.jsonl", output / f"{name}.stdout.log", output / f"{name}.stderr.log"
            command = [str(executable), str(models / spec["filename"]), "--cpu", "--report", str(report)]
            if name == "qwen35": command.append("--qwen35")
            metadata["commands"].append(command); save()
            print(f"Evaluating supplemental production catalog: {name}", flush=True)
            with stdout_path.open("w") as stdout, stderr_path.open("w") as stderr:
                process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=stderr, text=True)
                progress = 0
                for line in process.stdout:
                    stdout.write(line); stdout.flush()
                    if line.startswith(("PASS ", "FAIL ")):
                        progress += 1
                        print(f"{name} supplemental case {progress}: {line.split()[0]}", flush=True)
                exit_code = process.wait()
            rows = [json.loads(line) for line in report.read_text().splitlines() if line]
            metadata["summary"][name] = summarize(rows, stdout_path.read_text(), exit_code)
            metadata["exitCodes"][name] = exit_code
            metadata["reportSHA256"][name] = digest(report)
            metadata["stdoutSHA256"][name] = digest(stdout_path)
            metadata["stderrSHA256"][name] = digest(stderr_path)
            metadata["inputBindings"][name] = [{"kind": row["kind"], "caseID": row["caseID"], "inputSHA256": text_digest(row["input"]),
                "recordsSHA256": text_digest(json.dumps(row["records"], sort_keys=True, ensure_ascii=False, separators=(",", ":"))),
                "promptSHA256": text_digest(row["prompt"]), "responseGrammarSHA256": text_digest(row["responseGrammar"]),
                "replyPromptSHA256": text_digest(row["replyPrompt"]) if row.get("replyPrompt") else None} for row in rows]
            stage_bindings = [binding for row in rows if (binding := bind_visit_stages(row, raw_output_field="rawOutput")) is not None]
            if len(stage_bindings) != sum(row.get("kind") == "visit" for row in rows):
                raise RuntimeError("A production visit row is missing its separately labelled stage evidence.")
            metadata.setdefault("visitStageBindings", {})[name] = stage_bindings
            save()
            print(f"{name} supplemental complete: {json.dumps(metadata['summary'][name], sort_keys=True)}", flush=True)
        metadata["complete"] = True
    finally:
        metadata["finishedUTC"] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()
    print(f"Complete supplemental model evidence: {output}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Supplemental model evaluation failed: {error}")
