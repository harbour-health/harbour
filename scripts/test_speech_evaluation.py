"""Deterministic scorer tests; generated WAVs are test doubles, not speech evidence."""
import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import wave

import speech_evaluation as evaluation


class SpeechEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.plan = {
            "schema_version": 1, "suite_id": "test-medication-asr-v1", "kind": "medication",
            "minimum_speakers": 2, "conditions": ["quiet", "background_noise"],
            "cases": [
                {"id": "isolated", "locale": "en-CA", "utterance_type": "isolated",
                 "reference": "Levothyroxine", "targets": [
                     {"text": "Levothyroxine", "start": 0, "end": 1, "variants": ["levo thyroxine"]}]},
                {"id": "sentence", "locale": "en-CA", "utterance_type": "sentence", "group": "difficult",
                 "reference": "I take levothyroxine daily.", "targets": [
                     {"text": "levothyroxine", "start": 2, "end": 3, "variants": ["levo thyroxine"]}]}
            ]}
        self.plan_path = self.write_json("plan.json", self.plan)
        self.manifest = {"schema_version": 1, "suite_id": self.plan["suite_id"],
                         "plan_sha256": evaluation.sha256(self.plan_path), "recordings": []}
        self.manifest_path = self.root / "recordings.json"

    def write_json(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value, ensure_ascii=False) + "\n", encoding="utf-8")
        return path

    def corpus(self):
        # Distinct tiny PCM buffers exercise hashing/format validation only.
        for case in self.plan["cases"]:
            for condition in self.plan["conditions"]:
                for speaker in ("speaker-a", "speaker-b"):
                    number = len(self.manifest["recordings"]) + 1
                    filename = f"recording-{number}.wav"
                    with wave.open(str(self.root / filename), "wb") as audio:
                        audio.setnchannels(1)
                        audio.setsampwidth(2)
                        audio.setframerate(8000)
                        audio.writeframes(struct.pack("<h", number) * 80)
                    self.manifest["recordings"].append({
                        "id": "recording-" + str(number), "case_id": case["id"], "speaker_id": speaker,
                        "condition": condition, "locale": case["locale"], "audio_path": filename,
                        "audio_sha256": evaluation.sha256(self.root / filename),
                        "reference": case["reference"], "reference_verified": True,
                        "provenance": {"source_type": "human", "recorded_at": "2026-11-18T12:00:00Z",
                                       "device": "unit-test fixture", "os": "unit-test fixture",
                                       "rights": "TEST DOUBLE ONLY; no human audio in these tests",
                                       "notes": "Synthetic PCM bytes are never published as acoustic evidence"}})
        self.write_json("recordings.json", self.manifest)
        return self.manifest["recordings"]

    def bundle(self, system_id="system-a"):
        self.write_json("recordings.json", self.manifest)
        return {"schema_version": 1, "suite_id": self.plan["suite_id"],
                "plan_sha256": evaluation.sha256(self.plan_path),
                "recordings_sha256": evaluation.sha256(self.manifest_path),
                "system": {"id": system_id, "recognizer": "fixture recognizer", "model": "fixture model",
                           "version": "1", "locales": ["en-CA"], "device": "fixture device",
                           "os": "fixture OS", "settings": {"hints": []}},
                "results": [{"recording_id": row["id"], "audio_sha256": row["audio_sha256"],
                             "locale": row["locale"], "status": "ok", "transcript": row["reference"]}
                            for row in self.manifest["recordings"]]}

    def run_evaluation(self, bundles):
        self.write_json("recordings.json", self.manifest)
        paths = [self.write_json(f"system-{index}.json", bundle) for index, bundle in enumerate(bundles)]
        return evaluation.evaluate(self.plan_path, self.manifest_path, paths)

    def test_normalizer_retains_accents_and_splits_punctuation(self):
        self.assertEqual(evaluation.tokens("JE prends l’acétaminophène—25."),
                         ["je", "prends", "l", "acétaminophène", "25"])
        self.assertNotEqual(evaluation.tokens("María"), evaluation.tokens("Maria"))
        self.assertEqual(evaluation.tokens("Ｉ TAKE"), ["i", "take"])

    def test_wer_reports_substitutions_deletions_and_insertions(self):
        target = [{"text": "two", "start": 1, "end": 2, "variants": []}]
        result = evaluation.score("one two three", "one too three extra", target)
        self.assertEqual(result["words"], {"substitution": 1, "deletion": 0, "insertion": 1,
                                          "reference_words": 3, "wer": 2 / 3})
        self.assertEqual(evaluation.score("one two three", "one three", target)["words"]["deletion"], 1)
        self.assertEqual(evaluation.score("one two three", "", target)["words"]["deletion"], 3)

    def test_split_variant_is_accepted_without_changing_strict_or_wer(self):
        case = self.plan["cases"][1]
        scored = evaluation.score(case["reference"], "I take levo thyroxine daily", case["targets"])
        self.assertFalse(scored["targets"][0]["strict"])
        self.assertTrue(scored["targets"][0]["accepted"])
        self.assertEqual(scored["targets"][0]["accepted_variant"], "levo thyroxine")
        self.assertGreater(scored["words"]["wer"], 0)

    def test_target_copied_elsewhere_does_not_mask_wrong_name(self):
        case = self.plan["cases"][1]
        result = evaluation.score(case["reference"], "I take aspirin daily and levothyroxine", case["targets"])
        self.assertFalse(result["targets"][0]["strict"])
        self.assertFalse(result["targets"][0]["accepted"])
        missing = evaluation.score(case["reference"], "I take daily", case["targets"])
        self.assertFalse(missing["targets"][0]["accepted"])

    def test_compound_name_and_boundary_insertions_are_not_silently_accepted(self):
        target = [{"text": "María García", "start": 2, "end": 4, "variants": ["María Elena García"]}]
        result = evaluation.score("I saw María García yesterday", "I saw María Elena García yesterday", target)
        self.assertFalse(result["targets"][0]["strict"])
        self.assertTrue(result["targets"][0]["accepted"])
        isolated = evaluation.score("Levothyroxine", "Levothyroxine sodium", self.plan["cases"][0]["targets"])
        self.assertFalse(isolated["targets"][0]["strict"])

    def test_complete_comparison_has_expected_groups_and_same_corpus(self):
        self.corpus()
        report = self.run_evaluation([self.bundle(), self.bundle("system-b")])
        self.assertTrue(report["complete"])
        self.assertTrue(report["coverage"]["corpus_complete"])
        self.assertEqual(report["systems"][0]["metrics"]["names"]["strict_accuracy"], 1)
        self.assertEqual(report["systems"][0]["metrics"]["words"]["wer"], 0)
        self.assertIn("sentence", report["systems"][0]["groups"]["case_id"])
        self.assertEqual(report["paired_comparisons"][0]["common_successful_recordings"], 8)
        self.assertTrue(report["paired_comparisons"][0]["same_corpus"])
        self.assertIn("rights", report["systems"][0]["recordings"][0]["provenance"])

    def test_failed_and_missing_rows_stay_in_operational_denominators(self):
        self.corpus()
        first, second = self.bundle(), self.bundle("system-b")
        first["results"].pop()
        first["results"][0].update(status="error", error="Recognizer unavailable", transcript="partial")
        report = self.run_evaluation([first, second])
        self.assertFalse(report["complete"])
        metrics = report["systems"][0]["metrics"]
        self.assertEqual((metrics["recordings"], metrics["ok"], metrics["missing"], metrics["errors"]), (8, 6, 1, 1))
        self.assertEqual(metrics["names"]["total"], 8)
        self.assertEqual(metrics["names"]["strict_correct"], 6)
        self.assertGreater(metrics["words"]["deletion"], 0)
        self.assertEqual(report["systems"][0]["successful_only_metrics"]["recordings"], 6)
        self.assertEqual(report["systems"][0]["recordings"][0]["transcript"], "partial")
        self.assertFalse(report["paired_comparisons"][0]["complete_outputs"])
        self.assertEqual(report["paired_comparisons"][0]["common_successful_recordings"], 6)

    def test_empty_success_is_measured_as_deletions(self):
        self.corpus()
        bundle = self.bundle()
        bundle["results"][0]["transcript"] = ""
        report = self.run_evaluation([bundle, self.bundle("system-b")])
        self.assertTrue(report["complete"])
        self.assertEqual(report["systems"][0]["recordings"][0]["score"]["words"]["deletion"], 1)
        self.assertEqual(report["systems"][0]["metrics"]["names"]["strict_correct"], 7)

    def test_no_recordings_produce_no_metrics_or_completion(self):
        report = self.run_evaluation([self.bundle(), self.bundle("system-b")])
        self.assertFalse(report["complete"])
        self.assertEqual(report["coverage"]["recordings"], 0)
        self.assertEqual(len(report["coverage"]["missing_cells"]), 4)
        self.assertIsNone(report["systems"][0]["metrics"])
        self.assertIsNone(report["paired_comparisons"][0]["common_set_metrics"]["system-a"])

    def test_one_system_or_insufficient_speakers_cannot_complete(self):
        self.corpus()
        self.assertFalse(self.run_evaluation([self.bundle()])["complete"])
        self.manifest["recordings"] = [r for r in self.manifest["recordings"] if r["speaker_id"] == "speaker-a"]
        report = self.run_evaluation([self.bundle(), self.bundle("system-b")])
        self.assertFalse(report["complete"])
        self.assertFalse(report["coverage"]["corpus_complete"])
        self.assertTrue(all(cell["speakers_observed"] == 1 for cell in report["coverage"]["missing_cells"]))

    def test_plan_rejects_invalid_spans_variants_and_duplicate_ids(self):
        for mutation in ("span", "variant", "duplicate", "boolean", "condition"):
            with self.subTest(mutation=mutation):
                plan = copy.deepcopy(self.plan)
                if mutation == "span":
                    plan["cases"][1]["targets"][0]["start"] = 1
                elif mutation == "variant":
                    plan["cases"][0]["targets"][0]["variants"] = ["LEVOTHYROXINE"]
                elif mutation == "duplicate":
                    plan["cases"].append(plan["cases"][0])
                elif mutation == "boolean":
                    plan["minimum_speakers"] = True
                else:
                    plan["conditions"] = ["quiet"]
                with self.assertRaises(evaluation.EvaluationError):
                    evaluation.validate_plan(plan)

    def test_recording_validation_rejects_invalid_provenance_paths_and_digests(self):
        self.corpus()
        for mutation in ("hash", "escape", "synthetic", "unverified", "reference", "timestamp", "rights", "relabel"):
            with self.subTest(mutation=mutation):
                manifest = copy.deepcopy(self.manifest)
                row = manifest["recordings"][0]
                if mutation == "hash":
                    row["audio_sha256"] = "0" * 64
                elif mutation == "escape":
                    row["audio_path"] = "../outside.wav"
                elif mutation == "synthetic":
                    row["provenance"]["source_type"] = "tts"
                elif mutation == "unverified":
                    row["reference_verified"] = False
                elif mutation == "reference":
                    row["reference"] = "aspirin"
                elif mutation == "timestamp":
                    row["provenance"]["recorded_at"] = "2026-11-18T12:00:00"
                elif mutation == "rights":
                    row["provenance"]["rights"] = ""
                else:
                    manifest["recordings"][1]["audio_path"] = row["audio_path"]
                    manifest["recordings"][1]["audio_sha256"] = row["audio_sha256"]
                with self.assertRaises(evaluation.EvaluationError):
                    evaluation.validate_recordings(manifest, self.plan, evaluation.sha256(self.plan_path), self.root)

    def test_truncated_audio_cannot_be_published_with_updated_hash(self):
        self.corpus()
        row = self.manifest["recordings"][0]
        path = self.root / row["audio_path"]
        path.write_bytes(path.read_bytes()[:-20])
        row["audio_sha256"] = evaluation.sha256(path)
        with self.assertRaises(evaluation.EvaluationError):
            evaluation.validate_recordings(self.manifest, self.plan, evaluation.sha256(self.plan_path), self.root)

    def test_results_reject_unknown_duplicate_mismatched_and_nonfinite_metadata(self):
        self.corpus()
        for mutation in ("unknown", "duplicate", "hash", "locale", "manifest", "latency", "system_locale"):
            with self.subTest(mutation=mutation):
                bundle = self.bundle()
                row = bundle["results"][0]
                if mutation == "unknown":
                    row["recording_id"] = "unknown"
                elif mutation == "duplicate":
                    bundle["results"].append(row)
                elif mutation == "hash":
                    row["audio_sha256"] = "0" * 64
                elif mutation == "locale":
                    row["locale"] = "fr-CA"
                elif mutation == "manifest":
                    bundle["recordings_sha256"] = "0" * 64
                elif mutation == "latency":
                    row["latency_ms"] = float("nan")
                else:
                    bundle["system"]["locales"] = ["fr-CA"]
                with self.assertRaises(evaluation.EvaluationError):
                    self.run_evaluation([bundle])
        with self.assertRaises(evaluation.EvaluationError):
            self.run_evaluation([self.bundle(), self.bundle()])

    def test_json_duplicate_keys_and_nonfinite_values_are_rejected(self):
        for content in ('{"id":1,"id":2}', '{"value":NaN}'):
            path = self.root / "invalid.json"
            path.write_text(content, encoding="utf-8")
            with self.assertRaises(evaluation.EvaluationError):
                evaluation.read_json(path)

    def test_cli_plan_validation_has_no_fabricated_metrics_and_preserves_output(self):
        script = Path(evaluation.__file__)
        destination = self.root / "validation.json"
        command = [sys.executable, str(script), "--plan", str(self.plan_path), "--validate-plan",
                   "--output", str(destination)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(destination.read_text(encoding="utf-8"))
        self.assertEqual(report["status"], "awaiting_recordings")
        self.assertIsNone(report["metrics"])
        original = destination.read_bytes()
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
        self.assertEqual(destination.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
