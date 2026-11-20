import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from controller import run_workflow
from patches import Candidate


def review(continue_review=False):
    record = {key: "evidence" for key in (
        "trigger", "expected_behavior", "evidence", "current_oracle", "alignment",
        "execution_evidence", "changes", "uncertainty")}
    record.update(decision="keep", patch_changed=False, continue_review=continue_review,
                  stop_reason="continue" if continue_review else "aligned")
    return {"exit_status": "Submitted", "submission": json.dumps(record)}


class FakeSession:
    def __init__(self, outcomes, budget):
        self.outcomes, self.budget = iter(outcomes), budget
        self.continuations = []

    def run_until_submission(self):
        self.budget.charge(1, 0.01)
        return next(self.outcomes)

    def continue_with(self, task):
        self.continuations.append(task)


class ControllerTests(unittest.TestCase):
    def execute(self, method, candidates, outcomes):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.sessions = []
        self.tasks = []

        def factory(role, task, budget, limits, directory):
            session = FakeSession([{"exit_status": "Submitted"}] if role == "generator" else outcomes, budget)
            self.sessions.append(session)
            self.tasks.append((role, task))
            return session

        config = {"total_limits": {"model_calls": 30, "estimated_cost_usd": 1, "seconds": 600},
                  "experimental_generation_limits": {"model_calls": 20, "estimated_cost_usd": .6, "seconds": 360},
                  "test_roots_by_repo": {"django/django": ["tests"]}, "max_review_rounds": 3}
        self.directory = Path(temporary.name) / "run"
        with patch("controller.capture_candidate", side_effect=candidates):
            return run_workflow(instance={"repo": "django/django", "instance_id": "example", "problem_statement": "Original issue"},
                                method=method, env=None, config=config, run_directory=self.directory,
                                session_factory=factory, reviewer_prompt="Review instructions", clock=lambda: 0)

    def test_baseline_has_no_reviewer(self):
        result = self.execute("baseline", [Candidate("original", ["tests/a.py"], True, "captured")], [])
        self.assertEqual(len(self.sessions), 1)
        self.assertEqual(result["review_rounds"], 0)

    def test_review_rounds_reuse_session_and_share_usage(self):
        good = Candidate("original", ["tests/a.py"], True, "captured")
        result = self.execute("oracle_review", [good, good, good], [review(True), review()])
        self.assertEqual(len(self.sessions), 2)
        self.assertEqual(len(self.sessions[1].continuations), 1)
        self.assertEqual(result["budget"]["model_calls"], 3)
        self.assertEqual(result["stop_reason"], "aligned")
        self.assertEqual(result["evaluation"], "not run")

    def test_invalid_revision_keeps_original_patch(self):
        good = Candidate("original", ["tests/a.py"], True, "captured")
        bad = Candidate("", ["source.py"], False, "disallowed_paths")
        result = self.execute("oracle_review", [good, bad], [review()])
        self.assertEqual(result["stop_reason"], "invalid_revision_fallback")
        self.assertEqual((self.directory / "prediction.patch").read_text(), "original")

    def test_no_candidate_skips_review(self):
        result = self.execute("oracle_review", [Candidate("", [], False, "no_changes")], [])
        self.assertEqual(len(self.sessions), 1)
        self.assertIsNone(result["selected_checkpoint"])

    def test_round_limit_and_malformed_records(self):
        good = Candidate("original", ["tests/a.py"], True, "captured")
        result = self.execute("oracle_review", [good] * 4,
                              [{"exit_status": "Submitted", "submission": "bad JSON"}] * 3)
        self.assertEqual(result["review_rounds"], 3)
        self.assertEqual(result["stop_reason"], "round_limit")


if __name__ == "__main__":
    unittest.main()
