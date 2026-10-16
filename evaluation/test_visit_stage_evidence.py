import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from visit_stage_evidence import bind_visit_stages


def complete_row():
    decisions = [{"id": 0, "kinds": ["none"]}]
    output = '{"medicines":[],"followUps":[],"appointments":[],"highlights":[]}'
    return dict(caseID="synthetic-evidence-control", kind="visit", effort="standard", repeatIndex=0,
                outputKind="application_assembled_model_stages", output=output,
                visitExtractionTrace=dict(outputOrigin="application_assembled_model_stages", modelID="control-model",
                    units=[dict(id=0, text="An ordinary source note.")], classifications=decisions,
                    stages=[dict(request=dict(id="classify", unitIDs=[0], prompt="Logical prompt", grammar="Actual grammar", maximumTokens=650),
                                 generation=dict(output=json.dumps(dict(units=decisions)), preparedPrompt="Actual prepared prompt", modelID="control-model"), seconds=0)],
                    classificationCoverageComplete=True, completed=True, assembledOutput=output, errors=[]))


class VisitStageEvidenceTests(unittest.TestCase):
    def test_legacy_evidence_is_separate_and_staged_origin_cannot_be_omitted(self):
        self.assertIsNone(bind_visit_stages(dict(kind="visit", output="legacy raw output")))
        row = complete_row()
        del row["outputKind"]
        with self.assertRaises(ValueError):
            bind_visit_stages(row)

    def test_actual_prompt_grammar_output_and_total_work_are_bound(self):
        row = complete_row()
        original = bind_visit_stages(row)
        self.assertEqual((original["generationCalls"], original["maximumRequestedTokens"]), (1, 650))
        changed = copy.deepcopy(row)
        changed["visitExtractionTrace"]["stages"][0]["generation"]["preparedPrompt"] += " changed"
        self.assertNotEqual(bind_visit_stages(changed)["traceSHA256"], original["traceSHA256"])
        self.assertNotEqual(bind_visit_stages(changed)["stages"][0]["preparedPromptSHA256"], original["stages"][0]["preparedPromptSHA256"])

    def test_probe_output_schema_is_explicit_without_rewriting_original_fields(self):
        row = complete_row()
        row["rawOutput"] = row.pop("output")
        with self.assertRaises(ValueError):
            bind_visit_stages(row)
        before = copy.deepcopy(row)
        self.assertEqual(bind_visit_stages(row, raw_output_field="rawOutput")["primaryOutputField"], "rawOutput")
        self.assertEqual(row, before)

    def test_success_cannot_hide_missing_prepared_prompt_or_changed_assembly(self):
        for change in ["prompt", "assembly"]:
            row = complete_row()
            if change == "prompt":
                del row["visitExtractionTrace"]["stages"][0]["generation"]["preparedPrompt"]
            else:
                row["output"] = "a different assembly"
            with self.assertRaises(ValueError):
                bind_visit_stages(row)

    def test_success_cannot_change_raw_classification_or_skip_selected_unit(self):
        row = complete_row()
        row["visitExtractionTrace"]["classifications"][0]["kinds"] = ["highlight"]
        with self.assertRaises(ValueError):
            bind_visit_stages(row)
        row["visitExtractionTrace"]["stages"][0]["generation"]["output"] = json.dumps(dict(units=row["visitExtractionTrace"]["classifications"]))
        with self.assertRaises(ValueError):
            bind_visit_stages(row)

    def test_failed_generation_retains_attempt_and_error_without_success_claim(self):
        row = complete_row()
        trace = row["visitExtractionTrace"]
        trace["completed"] = False
        trace["errors"] = ["context preparation failed"]
        trace["stages"][0]["error"] = "context preparation failed"
        del trace["stages"][0]["generation"]
        result = bind_visit_stages(row)
        self.assertFalse(result["completed"])
        self.assertEqual(result["generationCalls"], 1)
        self.assertTrue(result["stages"][0]["errorSHA256"])


if __name__ == "__main__":
    unittest.main()
