#!/usr/bin/env python3
"""Score human-recorded ASR output separately from medication/name matching.

Tokens use Unicode NFKC and casefold; punctuation, hyphens and apostrophes
separate tokens. Accents remain significant. Reference target spans use these
zero-based tokens, with an exclusive end. Missing/error outputs are empty
hypotheses for operational WER and name accuracy, never dropped observations.
"""
import argparse
from collections import defaultdict
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import platform
import re
import sys
import unicodedata
import wave


NORMALIZER = "unicode-nfkc-casefold-alphanumeric-v1"


class EvaluationError(ValueError):
    """Invalid or mismatched evidence; no score should be published."""


def tokens(text):
    text = unicodedata.normalize("NFKC", text).casefold()
    return "".join(
        char if char.isalnum() or unicodedata.category(char).startswith("M") else " "
        for char in text
    ).split()


def sha256(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def _pairs(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise EvaluationError("Duplicate JSON key: " + key)
        value[key] = item
    return value


def _constant(value):
    raise EvaluationError("Non-finite JSON number: " + value)


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"),
                          object_pairs_hook=_pairs, parse_constant=_constant)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise EvaluationError(f"Cannot read {path}: {error}") from error


def _fields(value, required, optional=(), label="object"):
    if not isinstance(value, dict):
        raise EvaluationError(label + " must be an object")
    missing = set(required) - value.keys()
    extra = value.keys() - set(required) - set(optional)
    if missing or extra:
        raise EvaluationError(f"{label}: missing fields {sorted(missing)}, unknown fields {sorted(extra)}")


def _text(value, label, *, empty=False):
    if not isinstance(value, str) or (not empty and not value.strip()):
        raise EvaluationError(label + " must be " + ("a string" if empty else "a nonempty string"))
    if len(value) > 50000 or "\x00" in value:
        raise EvaluationError(label + " is too long or contains NUL")
    return value


def _identifier(value, label):
    _text(value, label)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", value):
        raise EvaluationError(label + " must be a portable identifier (letters, numbers, dot, underscore, hyphen)")
    return value


def _integer(value, minimum, maximum, label):
    if type(value) is not int or not minimum <= value <= maximum:
        raise EvaluationError(f"{label} must be an integer from {minimum} to {maximum}")


def _list(value, label, *, nonempty=False):
    if not isinstance(value, list) or (nonempty and not value):
        raise EvaluationError(label + " must be " + ("a nonempty list" if nonempty else "a list"))


def _locale(value, label):
    _text(value, label)
    if not re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})+", value):
        raise EvaluationError(label + " must be a locale such as en-CA or fr-CA")


def _digest(value, label):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise EvaluationError(label + " must be a lowercase SHA-256 digest")


def validate_plan(plan):
    _fields(plan, ["schema_version", "suite_id", "kind", "minimum_speakers", "conditions", "cases"], label="plan")
    _integer(plan["schema_version"], 1, 1, "schema_version")
    _identifier(plan["suite_id"], "suite_id")
    if plan["kind"] not in ("medication", "personal_name"):
        raise EvaluationError("kind must be medication or personal_name")
    _integer(plan["minimum_speakers"], 2, 1000, "minimum_speakers")
    _list(plan["conditions"], "conditions", nonempty=True)
    for condition in plan["conditions"]:
        _identifier(condition, "condition")
    if len(set(plan["conditions"])) != len(plan["conditions"]):
        raise EvaluationError("Duplicate condition")
    if not {"quiet", "background_noise"}.issubset(plan["conditions"]):
        raise EvaluationError("conditions must include quiet and background_noise")
    _list(plan["cases"], "cases", nonempty=True)
    cases = {}
    utterance_types = set()
    for case in plan["cases"]:
        _fields(case, ["id", "locale", "utterance_type", "reference", "targets"], ["group"], "case")
        case_id = _identifier(case["id"], "case.id")
        if case_id in cases:
            raise EvaluationError("Duplicate case: " + case_id)
        _locale(case["locale"], "case.locale")
        if case["utterance_type"] not in ("isolated", "sentence"):
            raise EvaluationError("utterance_type must be isolated or sentence")
        utterance_types.add(case["utterance_type"])
        _text(case["reference"], "case.reference")
        reference = tokens(case["reference"])
        if not reference or len(reference) > 500:
            raise EvaluationError("reference must contain 1 to 500 normalized tokens")
        if "group" in case:
            _identifier(case["group"], "case.group")
        _list(case["targets"], "targets", nonempty=True)
        occupied = set()
        for target in case["targets"]:
            _fields(target, ["text", "start", "end", "variants"], label="target")
            _text(target["text"], "target.text")
            _integer(target["start"], 0, len(reference) - 1, "target.start")
            _integer(target["end"], target["start"] + 1, len(reference), "target.end")
            if tokens(target["text"]) != reference[target["start"]:target["end"]]:
                raise EvaluationError("target.text does not match its normalized reference span")
            span = set(range(target["start"], target["end"]))
            if occupied & span:
                raise EvaluationError("Target spans overlap")
            occupied |= span
            _list(target["variants"], "target.variants")
            variants = {tuple(tokens(target["text"]))}
            for variant in target["variants"]:
                _text(variant, "target variant")
                normalized = tuple(tokens(variant))
                if not normalized or normalized in variants:
                    raise EvaluationError("Empty or duplicate normalized target variant")
                variants.add(normalized)
        cases[case_id] = case
    if utterance_types != {"isolated", "sentence"}:
        raise EvaluationError("Plan must include isolated and sentence utterances")
    return cases


def _wav(path):
    try:
        with wave.open(str(path), "rb") as audio:
            rate, frames = audio.getframerate(), audio.getnframes()
            channels, width = audio.getnchannels(), audio.getsampwidth()
            if audio.getcomptype() != "NONE" or channels not in (1, 2) or width not in (1, 2, 3, 4):
                raise EvaluationError("Audio must be mono/stereo uncompressed PCM WAV")
            if not 8000 <= rate <= 192000 or frames <= 0:
                raise EvaluationError("Audio must contain frames at a supported sample rate")
            expected = frames * channels * width
            observed = 0
            while True:
                chunk = audio.readframes(16384)
                if not chunk:
                    break
                observed += len(chunk)
            if observed != expected:
                raise EvaluationError("Truncated WAV frame payload")
            return {"sample_rate": rate, "channels": channels, "frames": frames,
                    "duration_seconds": frames / rate}
    except (OSError, EOFError, wave.Error) as error:
        raise EvaluationError(f"Invalid WAV {path}: {error}") from error


def validate_recordings(document, plan, plan_digest, directory):
    _fields(document, ["schema_version", "suite_id", "plan_sha256", "recordings"], label="recordings manifest")
    _integer(document["schema_version"], 1, 1, "recordings.schema_version")
    if document["suite_id"] != plan["suite_id"] or document["plan_sha256"] != plan_digest:
        raise EvaluationError("Recording manifest does not match frozen plan and digest")
    _list(document["recordings"], "recordings")
    cases = {case["id"]: case for case in plan["cases"]}
    root = Path(directory).resolve()
    recordings, hashes = {}, set()
    for recording in document["recordings"]:
        _fields(recording, ["id", "case_id", "speaker_id", "condition", "locale", "audio_path",
                            "audio_sha256", "reference", "reference_verified", "provenance"], label="recording")
        recording_id = _identifier(recording["id"], "recording.id")
        if recording_id in recordings:
            raise EvaluationError("Duplicate recording: " + recording_id)
        case_id = _identifier(recording["case_id"], "recording.case_id")
        if case_id not in cases:
            raise EvaluationError("Unknown recording case: " + case_id)
        case = cases[case_id]
        _identifier(recording["speaker_id"], "speaker_id")
        if recording["condition"] not in plan["conditions"]:
            raise EvaluationError("Recording condition is not in the frozen plan")
        if recording["locale"] != case["locale"]:
            raise EvaluationError("Recording locale does not match its case")
        _text(recording["reference"], "recording.reference")
        if recording["reference_verified"] is not True or tokens(recording["reference"]) != tokens(case["reference"]):
            raise EvaluationError("Recording must have a verified faithful reading of the frozen script")
        provenance = recording["provenance"]
        _fields(provenance, ["source_type", "recorded_at", "device", "os", "rights"],
                ["accent", "notes"], "recording.provenance")
        if provenance["source_type"] != "human":
            raise EvaluationError("This study requires human recordings, not synthetic speech")
        for field in ("recorded_at", "device", "os", "rights"):
            _text(provenance[field], "provenance." + field)
        for field in ("accent", "notes"):
            if field in provenance:
                _text(provenance[field], "provenance." + field)
        try:
            when = datetime.fromisoformat(provenance["recorded_at"].replace("Z", "+00:00"))
            if when.utcoffset() is None:
                raise ValueError("timezone required")
        except ValueError as error:
            raise EvaluationError("recorded_at must be an ISO-8601 timestamp with timezone") from error
        relative = _text(recording["audio_path"], "audio_path")
        portable = PurePosixPath(relative)
        if portable.is_absolute() or ".." in portable.parts or "\\" in relative or ":" in relative:
            raise EvaluationError("audio_path must be a portable relative path inside the manifest directory")
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or path.suffix.lower() != ".wav" or not path.is_file():
            raise EvaluationError("audio_path must identify a WAV inside the manifest directory")
        _digest(recording["audio_sha256"], "audio_sha256")
        actual_hash = sha256(path)
        if actual_hash != recording["audio_sha256"]:
            raise EvaluationError("Audio digest mismatch: " + recording_id)
        if actual_hash in hashes:
            raise EvaluationError("An audio file cannot be relabeled as multiple recordings")
        hashes.add(actual_hash)
        recordings[recording_id] = dict(recording, audio_format=_wav(path))
    return recordings


def validate_results(document, plan, plan_digest, manifest_digest, recordings):
    _fields(document, ["schema_version", "suite_id", "plan_sha256", "recordings_sha256", "system", "results"],
            label="result bundle")
    _integer(document["schema_version"], 1, 1, "results.schema_version")
    if (document["suite_id"] != plan["suite_id"] or document["plan_sha256"] != plan_digest
            or document["recordings_sha256"] != manifest_digest):
        raise EvaluationError("Result bundle does not match frozen plan and recording manifest")
    system = document["system"]
    _fields(system, ["id", "recognizer", "model", "version", "locales", "device", "os", "settings"], label="system")
    _identifier(system["id"], "system.id")
    for key in ("recognizer", "model", "version", "device", "os"):
        _text(system[key], "system." + key)
    _list(system["locales"], "system.locales", nonempty=True)
    for locale in system["locales"]:
        _locale(locale, "system.locale")
    if len(system["locales"]) != len(set(system["locales"])):
        raise EvaluationError("Duplicate system locale")
    if not isinstance(system["settings"], dict):
        raise EvaluationError("system.settings must be an object")
    _list(document["results"], "results")
    outputs = {}
    for row in document["results"]:
        _fields(row, ["recording_id", "audio_sha256", "locale", "status"],
                ["transcript", "error", "latency_ms"], "result")
        recording_id = _identifier(row["recording_id"], "result.recording_id")
        if recording_id in outputs or recording_id not in recordings:
            raise EvaluationError("Duplicate or unknown result recording: " + recording_id)
        recording = recordings[recording_id]
        if row["audio_sha256"] != recording["audio_sha256"]:
            raise EvaluationError("Result audio digest mismatch: " + recording_id)
        if row["locale"] != recording["locale"] or row["locale"] not in system["locales"]:
            raise EvaluationError("Result locale mismatch: " + recording_id)
        if row["status"] not in ("ok", "error"):
            raise EvaluationError("Result status must be ok or error")
        if row["status"] == "ok":
            _text(row.get("transcript"), "result.transcript", empty=True)
            if "error" in row:
                raise EvaluationError("Successful output must not contain an error")
        else:
            _text(row.get("error"), "result.error")
            if "transcript" in row:
                _text(row["transcript"], "result.transcript", empty=True)
        if "latency_ms" in row:
            latency = row["latency_ms"]
            if type(latency) not in (int, float) or not math.isfinite(latency) or latency < 0:
                raise EvaluationError("latency_ms must be a finite nonnegative number")
        outputs[recording_id] = row
    return system, outputs


def system_fingerprint(system):
    """Run labels cannot turn one declared recognizer configuration into two."""
    configuration = {key: value for key, value in system.items() if key != "id"}
    configuration["locales"] = sorted(configuration["locales"])
    encoded = json.dumps(configuration, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def align(reference, hypothesis):
    """Unit-cost token alignment, deterministically preferring diagonal ties."""
    rows, columns = len(reference), len(hypothesis)
    distance = [list(range(columns + 1))] + [[i] + [0] * columns for i in range(1, rows + 1)]
    for i in range(1, rows + 1):
        for j in range(1, columns + 1):
            distance[i][j] = min(distance[i - 1][j] + 1, distance[i][j - 1] + 1,
                                 distance[i - 1][j - 1] + (reference[i - 1] != hypothesis[j - 1]))
    i, j, operations = rows, columns, []
    while i or j:
        if i and j and distance[i][j] == distance[i - 1][j - 1] + (reference[i - 1] != hypothesis[j - 1]):
            operations.append(("match" if reference[i - 1] == hypothesis[j - 1] else "substitution", i - 1, j - 1))
            i -= 1
            j -= 1
        elif i and distance[i][j] == distance[i - 1][j] + 1:
            operations.append(("deletion", i - 1, None))
            i -= 1
        else:
            operations.append(("insertion", i, j - 1))
            j -= 1
    operations.reverse()
    return operations


def score(reference_text, hypothesis_text, targets):
    reference, hypothesis = tokens(reference_text), tokens(hypothesis_text)
    if not reference:
        raise EvaluationError("Cannot score an empty normalized reference")
    operations = align(reference, hypothesis)
    counts = {name: sum(op[0] == name for op in operations)
              for name in ("substitution", "deletion", "insertion")}
    counts["reference_words"] = len(reference)
    counts["wer"] = sum(counts[name] for name in ("substitution", "deletion", "insertion")) / len(reference)
    target_scores = []
    for target in targets:
        start, end = target["start"], target["end"]
        mapped = [j for op, i, j in operations if op in ("match", "substitution") and start <= i < end]
        inserted = [j for op, i, j in operations if op == "insertion" and start <= i <= end]
        deleted = any(op == "deletion" and start <= i < end for op, i, _ in operations)
        selected = mapped + inserted
        observed = hypothesis[min(selected):max(selected) + 1] if selected else []
        strict = not deleted and observed == tokens(target["text"])
        accepted, accepted_variant = strict, None
        if mapped and not strict:
            # Boundary insertions count conservatively as part of the name.
            # Never search the whole utterance for an unrelated copied name.
            for variant in target["variants"]:
                if observed == tokens(variant):
                    accepted, accepted_variant = True, variant
                    break
        target_scores.append({"text": target["text"], "observed": " ".join(observed),
                              "strict": strict, "accepted": accepted,
                              "accepted_variant": accepted_variant})
    return {"words": counts, "targets": target_scores}


def _metrics(rows):
    if not rows:
        return None
    words = {name: sum(row["score"]["words"][name] for row in rows)
             for name in ("substitution", "deletion", "insertion", "reference_words")}
    words["wer"] = sum(words[name] for name in ("substitution", "deletion", "insertion")) / words["reference_words"]
    names = [target for row in rows for target in row["score"]["targets"]]
    strict = sum(target["strict"] for target in names)
    accepted = sum(target["accepted"] for target in names)
    return {"recordings": len(rows), "ok": sum(row["status"] == "ok" for row in rows),
            "missing": sum(row["status"] == "missing" for row in rows),
            "errors": sum(row["status"] == "error" for row in rows), "words": words,
            "names": {"total": len(names), "strict_correct": strict, "accepted_correct": accepted,
                      "strict_accuracy": strict / len(names), "accepted_accuracy": accepted / len(names)}}


def evaluate(plan_path, recordings_path, result_paths):
    plan_path, recordings_path = Path(plan_path), Path(recordings_path)
    plan = read_json(plan_path)
    cases = validate_plan(plan)
    plan_digest = sha256(plan_path)
    manifest = read_json(recordings_path)
    recordings = validate_recordings(manifest, plan, plan_digest, recordings_path.parent)
    manifest_digest = sha256(recordings_path)
    systems, identifiers, configurations = [], set(), set()
    for result_path in result_paths:
        document = read_json(result_path)
        system, outputs = validate_results(document, plan, plan_digest, manifest_digest, recordings)
        if system["id"] in identifiers:
            raise EvaluationError("Duplicate system id: " + system["id"])
        fingerprint = system_fingerprint(system)
        if fingerprint in configurations:
            raise EvaluationError("Duplicate candidate configuration: " + system["id"])
        identifiers.add(system["id"])
        configurations.add(fingerprint)
        rows = []
        grouped = defaultdict(lambda: defaultdict(list))
        for recording_id, recording in recordings.items():
            case = cases[recording["case_id"]]
            raw = outputs.get(recording_id)
            status = raw["status"] if raw else "missing"
            transcript = raw.get("transcript", "") if raw else None
            scored = score(recording["reference"], transcript if status == "ok" else "", case["targets"])
            row = {"recording_id": recording_id, "case_id": case["id"], "speaker_id": recording["speaker_id"],
                   "locale": case["locale"], "condition": recording["condition"],
                   "utterance_type": case["utterance_type"], "group": case.get("group", "ungrouped"),
                   "audio_sha256": recording["audio_sha256"], "audio_format": recording["audio_format"],
                   "provenance": recording["provenance"],
                   "reference": recording["reference"], "status": status, "transcript": transcript,
                   "error": raw.get("error") if raw else "No result supplied", "score": scored}
            if raw and "latency_ms" in raw:
                row["latency_ms"] = raw["latency_ms"]
            rows.append(row)
            for dimension in ("case_id", "speaker_id", "locale", "condition", "utterance_type", "group"):
                grouped[dimension][row[dimension]].append(row)
        systems.append({"system": system, "configuration_sha256": fingerprint,
                        "results_sha256": sha256(result_path),
                        "metrics": _metrics(rows),
                        "successful_only_metrics": _metrics([row for row in rows if row["status"] == "ok"]),
                        "groups": {dimension: {value: _metrics(group) for value, group in values.items()}
                                   for dimension, values in grouped.items()}, "recordings": rows})
    missing_cells = []
    for case_id in cases:
        for condition in plan["conditions"]:
            speakers = {r["speaker_id"] for r in recordings.values()
                        if r["case_id"] == case_id and r["condition"] == condition}
            if len(speakers) < plan["minimum_speakers"]:
                missing_cells.append({"case_id": case_id, "condition": condition,
                                      "speakers_observed": len(speakers),
                                      "speakers_required": plan["minimum_speakers"]})
    paired = []
    for left_index, left in enumerate(systems):
        for right in systems[left_index + 1:]:
            common = {a["recording_id"] for a, b in zip(left["recordings"], right["recordings"])
                      if a["status"] == b["status"] == "ok"}
            paired.append({"systems": [left["system"]["id"], right["system"]["id"]],
                           "same_corpus": True, "recordings_expected": len(recordings),
                           "common_successful_recordings": len(common),
                           "complete_outputs": bool(recordings) and len(common) == len(recordings),
                           "common_set_metrics": {
                               item["system"]["id"]: _metrics([row for row in item["recordings"]
                                                                if row["recording_id"] in common])
                               for item in (left, right)}})
    corpus_complete = bool(recordings) and not missing_cells
    complete = corpus_complete and len(systems) >= 2 and all(
        row["status"] == "ok" for system in systems for row in system["recordings"])
    return {"schema_version": 1, "suite_id": plan["suite_id"], "normalizer": NORMALIZER,
            "runtime": {"python": platform.python_version(), "unicode_database": unicodedata.unidata_version},
            "plan_sha256": plan_digest, "recordings_sha256": manifest_digest,
            "scorer_sha256": sha256(Path(__file__)), "status": "complete" if complete else "incomplete",
            "complete": complete, "coverage": {"recordings": len(recordings),
                "systems": len(systems), "minimum_systems": 2, "corpus_complete": corpus_complete,
                "missing_cells": missing_cells},
            "wer_policy": "Missing/error outputs are empty hypotheses in operational metrics; successful-only metrics are separate.",
            "evidence_limit": "Human source and reference verification are collector attestations; scores do not establish clinical safety or population fairness.",
            "systems": systems, "paired_comparisons": paired}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True, type=Path)
    parser.add_argument("--recordings", type=Path)
    parser.add_argument("--results", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--validate-plan", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.validate_plan:
            if args.recordings or args.results:
                raise EvaluationError("--validate-plan does not accept recordings or results")
            plan = read_json(args.plan)
            cases = validate_plan(plan)
            report = {"schema_version": 1, "suite_id": plan["suite_id"], "plan_sha256": sha256(args.plan),
                      "runtime": {"python": platform.python_version(), "unicode_database": unicodedata.unidata_version},
                      "normalizer": NORMALIZER, "status": "awaiting_recordings", "complete": False,
                      "cases": len(cases), "metrics": None}
        else:
            if not args.recordings or not args.results or not args.output:
                raise EvaluationError("Scoring requires --recordings, at least one --results, and --output")
            report = evaluate(args.plan, args.recordings, args.results)
        output = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        if args.output:
            # Evidence files are immutable by default; require a fresh destination.
            with args.output.open("x", encoding="utf-8", newline="\n") as destination:
                destination.write(output)
        else:
            sys.stdout.buffer.write(output.encode("utf-8"))
    except (EvaluationError, OSError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
