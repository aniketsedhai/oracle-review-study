import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from controller import run_workflow
from patches import Candidate
from revision_check import check_revision_claim


def record(decision="keep", changed=False, command=""):
    value = {key: "evidence" for key in ("trigger", "expected_behavior", "evidence",
             "current_oracle", "alignment", "execution_evidence", "changes", "uncertainty")}
    value.update(decision=decision, patch_changed=changed, validation_command=command,
                 continue_review=False, stop_reason="aligned")
    return {"exit_status": "Submitted", "submission": json.dumps(value)}


class Environment:
    def __init__(self):
        self.commands = []

    def execute(self, action, **kwargs):
        self.commands.append((action, kwargs))
        return {"returncode": 1, "output": "Expected reported defect on buggy code", "exception_info": ""}


class Session:
    def __init__(self, outcomes, budget):
        self.outcomes, self.budget = iter(outcomes), budget
        self.continuations = []

    def run_until_submission(self):
        self.budget.charge(1, .01)
        return next(self.outcomes)

    def continue_with(self, task):
        self.continuations.append(task)


class RevisionGuardTests(unittest.TestCase):
    def run_case(self, candidates, outcomes, calls=30):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.output = Path(directory.name) / "run"
        self.env = Environment()
        self.sessions = []
        def factory(role, task, budget, limits, output):
            session = Session([{"exit_status": "Submitted"}] if role == "generator" else outcomes, budget)
            self.sessions.append(session)
            return session
        config = {"total_limits": {"model_calls": calls, "estimated_cost_usd": 1, "seconds": 600},
                  "experimental_generation_limits": {"model_calls": 20, "estimated_cost_usd": .6, "seconds": 360},
                  "test_roots_by_repo": {"example/repo": ["tests"]}, "max_review_rounds": 3}
        with patch("controller.capture_candidate", side_effect=candidates):
            return run_workflow(instance={"repo": "example/repo", "instance_id": "example", "problem_statement": "issue"},
                                method="oracle_review", env=self.env, config=config,
                                run_directory=self.output, session_factory=factory,
                                reviewer_prompt="Review", clock=lambda: 0)

    def test_archived_xarray_revision_claim_is_detected(self):
        # Replay the observed failure shape: claimed revision, identical patch.
        candidate = Candidate("same", ["tests/a.py"], True, "captured")
        claim = {"decision": "revise", "changes": "Relaxed the regex"}
        result = check_revision_claim(candidate, candidate, claim)
        self.assertIn("claimed_revision_without_patch_change", result["issues"])

    def test_false_claim_forces_correction_then_real_edit_is_executed(self):
        original = Candidate("original", ["tests/a.py"], True, "captured")
        fixed = Candidate("fixed", ["tests/a.py"], True, "captured")
        result = self.run_case([original, original, fixed, fixed],
                               [record("revise", True), record("revise", True, "python -m pytest tests/a.py")])
        self.assertEqual(result["review_rounds"], 2)
        self.assertEqual(result["stop_reason"], "aligned")
        self.assertEqual(result["revision_guard_failures"], 1)
        self.assertIn("claimed_revision_without_patch_change", self.sessions[1].continuations[0])
        self.assertEqual(self.env.commands[0][0]["command"], "set -o pipefail\npython -m pytest tests/a.py")
        self.assertEqual((self.output / "prediction.patch").read_text(), "fixed")
        self.assertFalse(result["selected_patch_validation_pending"])
        saved = json.loads((self.output / "reviewer/round-02/validation.json").read_text())
        self.assertEqual(saved["returncode"], 1)  # Buggy-code failure is acceptable.

    def test_repeated_false_claim_cannot_finish_as_aligned(self):
        original = Candidate("original", ["tests/a.py"], True, "captured")
        result = self.run_case([original] * 4, [record("revise", True)] * 3)
        self.assertEqual(result["stop_reason"], "unverified_revision_round_limit")
        self.assertEqual(result["revision_guard_failures"], 3)
        self.assertEqual(len(self.env.commands), 0)

    def test_exhausted_budget_preserves_patch_without_certifying_revision(self):
        original = Candidate("original", ["tests/a.py"], True, "captured")
        result = self.run_case([original, original], [record("revise", True)], calls=2)
        self.assertEqual(result["stop_reason"], "unverified_revision_resource_limit")
        self.assertEqual((self.output / "prediction.patch").read_text(), "original")

    def test_keep_without_edit_does_not_require_fake_revision(self):
        original = Candidate("original", ["tests/a.py"], True, "captured")
        result = self.run_case([original, original], [record()])
        self.assertEqual(result["stop_reason"], "aligned")
        self.assertEqual(result["revision_guard_failures"], 0)
        self.assertEqual(len(self.env.commands), 0)

    def test_validation_that_changes_files_falls_back(self):
        original = Candidate("original", ["tests/a.py"], True, "captured")
        fixed = Candidate("fixed", ["tests/a.py"], True, "captured")
        mutated = Candidate("mutated by validation", ["tests/a.py"], True, "captured")
        result = self.run_case([original, fixed, mutated], [record("revise", True, "pytest tests/a.py")])
        self.assertEqual(result["stop_reason"], "validation_modified_patch_fallback")
        self.assertEqual((self.output / "prediction.patch").read_text(), "original")
        self.assertFalse(result["selected_patch_validation_pending"])


if __name__ == "__main__":
    unittest.main()
