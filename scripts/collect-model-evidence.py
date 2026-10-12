#!/usr/bin/env python3
"""Record disjoint evaluation streams without merging or overwriting raw evidence.

All runs must share their exact fixture, executable, source and native runtime.
Cold model-load boundaries remain attached to their original process/run.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path

QUALITY_KINDS = {"routing", "prose", "title", "visit"}
IDENTITY_FIELDS = ["suiteSHA256", "executableSHA256", "sourceSHA256", "runtimeFilesSHA256", "swiftVersion", "platform", "processor", "logicalProcessors"]
INFERENCE_FIELDS = ["context", "batch", "threads", "backend", "sampling", "JSONStopping", "efforts", "repeats", "repeatScope", "tokenBudgets", "grammarPolicy", "baselinePrompts"]

def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1_048_576), b""):
            value.update(data)
    return value.hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", nargs="+", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error("Refusing to overwrite an existing collection manifest.")
    common = None
    seen = set()
    collections = []
    total_diagnostics = 0
    def reference(path):
        try:
            return Path(os.path.relpath(path, output.parent)).as_posix()
        except ValueError:
            return str(path)
    for directory in args.runs:
        directory = directory.resolve()
        metadata_path = directory / "metadata.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8-sig"))
        if metadata.get("complete") is not True:
            parser.error(f"Incomplete run: {directory}")
        identity = {field: metadata[field] for field in IDENTITY_FIELDS}
        identity["inferenceSettings"] = {field: metadata["settings"].get(field) for field in INFERENCE_FIELDS}
        identity["models"] = sorted(metadata["models"], key=lambda value: value["model"])
        if common is None:
            common = identity
        elif identity != common:
            parser.error(f"Source/binary/runtime/model/settings mismatch: {directory}")
        streams = []
        for spec in identity["models"]:
            name = spec["model"]
            if name not in {"small", "balanced", "qwen35"}:
                parser.error(f"Unknown model identity: {name}")
            stream = directory / f"{name}.jsonl"
            rows = [json.loads(line) for line in stream.read_text(encoding="utf-8-sig").splitlines() if line]
            cold = []
            quality = 0
            split_counts = {}
            for row in rows:
                if row.get("model") != name:
                    parser.error(f"Unexpected model in {stream}")
                if row["kind"] not in QUALITY_KINDS:
                    continue
                if metadata["settings"]["split"] != "all" and row["split"] != metadata["settings"]["split"]:
                    parser.error(f"Split mismatch in {stream}")
                key = (name, row["caseID"], row.get("effort", "standard"), row.get("repeatIndex", 0))
                if key in seen:
                    parser.error(f"Duplicate quality run: {key}")
                seen.add(key)
                quality += 1
                split_counts[row["split"]] = split_counts.get(row["split"], 0) + 1
                if row.get("coldLoad"):
                    cold.append({field: row[field] for field in ["caseID", "split", "effort", "repeatIndex", "seconds"]})
            diagnostics = len(rows) - quality
            total_diagnostics += diagnostics
            streams.append({"model": name, "path": reference(stream), "sha256": digest(stream), "bytes": stream.stat().st_size,
                "qualityRows": quality, "diagnosticRows": diagnostics, "splitCounts": split_counts, "coldBoundaries": cold})
        collections.append({"sourceLabel": metadata["sourceLabel"], "metadata": reference(metadata_path), "metadataSHA256": digest(metadata_path),
            "startedUTC": metadata["startedUTC"], "finishedUTC": metadata["finishedUTC"], "streams": streams})
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = {"formatVersion": 1, "createdUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "collectorSHA256": digest(Path(__file__)), "identity": common, "uniqueQualityRows": len(seen), "diagnosticRows": total_diagnostics,
        "streams": [{"rows": stream["path"], "rowsSHA256": stream["sha256"], "metadata": run["metadata"], "metadataSHA256": run["metadataSHA256"]} for run in collections for stream in run["streams"]],
        "runs": collections, "timingPolicy": "Retain each process/run cold boundary; compare warm requests separately. No additional quality samples are inferred from collection."}
    with output.open("x", encoding="utf-8", newline="\n") as destination:
        json.dump(manifest, destination, indent=2)
        destination.write("\n")
    print(f"Collected {len(seen)} distinct quality rows: {output}")

if __name__ == "__main__":
    main()
