import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("model_probe_runner", Path(__file__).resolve().parent.parent / "scripts/evaluate-model-probe.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class SupplementalCompletionTests(unittest.TestCase):
    def rows(self, matched=True):
        return [
            {"kind": "routing", "caseID": "routing.0", "fixtureMatched": matched, "expectedTool": "reply", "acceptedAction": {"type": "reply"}},
            {"kind": "visit", "caseID": "source-visit", "fixtureMatched": True, "fallbackUsed": False, "rejectedMedicineProposals": 0},
        ]

    def summary(self, passed=1):
        return f"{passed}/1 model routing cases passed\n1/1 transcript cases passed\n"

    def test_completed_quality_failure_is_reported(self):
        result = RUNNER.summarize(self.rows(False), self.summary(0), 1)
        self.assertEqual(result["routing"], {"passed": 0, "total": 1})
        self.assertTrue(result["manualSourceAndSafetyReviewRequired"])

    def test_missing_catalog_is_incomplete(self):
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(self.rows(), "1/1 model routing cases passed\n", 1)

    def test_native_fatal_exit_is_incomplete(self):
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(self.rows(), self.summary(), 134)

    def test_report_cannot_omit_a_case(self):
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(self.rows()[:-1], self.summary(), 0)

    def test_report_and_native_match_counts_must_agree(self):
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(self.rows(False), self.summary(), 0)

    def test_duplicate_case_ids_are_rejected(self):
        rows = self.rows() + [self.rows()[0]]
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(rows, "2/2 model routing cases passed\n1/1 transcript cases passed\n", 0)

    def test_quality_exit_status_cannot_disagree(self):
        with self.assertRaises(RuntimeError):
            RUNNER.summarize(self.rows(), self.summary(), 1)

    def test_semantic_period_policy_preserves_legacy_failure(self):
        rows = self.rows()
        rows[1]["fixtureMatched"] = False
        rows[1]["semanticFixtureMatched"] = True
        result = RUNNER.summarize(rows, "1/1 model routing cases passed\n0/1 transcript cases passed\n", 1)
        self.assertEqual(result["visit"], {"passed": 0, "total": 1})
        self.assertEqual(result["visitSemantic"], {"passed": 1, "total": 1})
        self.assertEqual(result["terminalPeriodOnlyDifferences"], ["source-visit"])
        self.assertTrue(result["fixtureMedicineAndAppointmentRecallWithoutFallback"])

    def test_fallback_and_accepted_wrong_tool_are_separate(self):
        rows = self.rows(False)
        rows[0]["acceptedAction"] = {"type": "create_appointment"}
        rows[1]["fallbackUsed"] = True
        rows[1]["rejectedMedicineProposals"] = 2
        result = RUNNER.summarize(rows, self.summary(0), 1)
        self.assertEqual(result["acceptedUnexpectedTools"], ["routing.0"])
        self.assertEqual(result["fallbackVisits"], 1)
        self.assertEqual(result["rejectedMedicineProposals"], 2)


if __name__ == "__main__":
    unittest.main()
