"""Compare workflow decisions with frozen controllers, without making API calls."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import controller
from patches import Candidate
from run_batch import make_jobs


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


original = load_module("original_controller", ROOT / "historical/original-30-call/scripts/controller.py")
sys.modules["revision_check"] = load_module(
    "revision_check", ROOT / "follow-up/verified-edits-v1/scripts/revision_check.py")
verified = load_module("verified_controller", ROOT / "follow-up/verified-edits-v1/scripts/controller.py")


class Session:
    def __init__(self, outcomes, budget):
        self.outcomes = iter(outcomes)
        self.budget = budget
        self.continuations = []

    def run_until_submission(self):
        self.budget.charge(1, .01)
        return next(self.outcomes)

    def continue_with(self, message):
        self.continuations.append(message)


class Environment:
    def execute(self, action, **kwargs):
        return {"returncode": 1, "output": "reported bug", "exception_info": ""}


def review(changed=False, continue_review=False):
    fields = ["trigger", "expected_behavior", "evidence", "current_oracle",
              "alignment", "execution_evidence", "changes", "uncertainty"]
    record = dict.fromkeys(fields, "evidence")
    record.update(decision="revise" if changed else "keep", patch_changed=changed,
                  validation_command="pytest tests/a.py" if changed else "",
                  continue_review=continue_review,
                  stop_reason="continue" if continue_review else "aligned")
    return {"exit_status": "Submitted", "submission": json.dumps(record)}


class RefactorTests(unittest.TestCase):
    def run_case(self, module, method, candidates, outcomes):
        with tempfile.TemporaryDirectory() as directory:
            run = Path(directory) / "run"
            config = {
                "total_limits": {"model_calls": 30, "estimated_cost_usd": 1, "seconds": 600},
                "experimental_generation_limits": {"model_calls": 20, "estimated_cost_usd": .6, "seconds": 360},
                "max_review_rounds": 3, "test_roots_by_repo": {"example/repo": ["tests"]},
            }
            sessions = []
            def factory(role, task, budget, limits, output):
                session = Session([{"exit_status": "Submitted"}] if role == "generator" else outcomes, budget)
                sessions.append(session)
                return session
            with patch.object(module, "capture_candidate", side_effect=candidates):
                result = module.run_workflow(
                    instance={"instance_id": "example", "repo": "example/repo", "problem_statement": "issue"},
                    method=method, env=Environment(), config=config, run_directory=run,
                    session_factory=factory, reviewer_prompt="Review", clock=lambda: 0,
                )
            fields = ["selected_checkpoint", "stop_reason", "generation_outcome",
                      "review_rounds", "budget", "evaluation"]
            result = {key: result[key] for key in fields}
            result["patch"] = (run / "prediction.patch").read_text()
            result["session_count"] = len(sessions)
            result["continuation_count"] = sum(len(s.continuations) for s in sessions)
            return result

    def test_original_controller_decisions_are_preserved(self):
        good = Candidate("original", ["tests/a.py"], True, "captured")
        edited = Candidate("edited", ["tests/a.py"], True, "captured")
        bad = Candidate("", ["production.py"], False, "disallowed_paths")
        cases = [
            ("baseline", [good], []),
            ("oracle_review", [good, good], [review()]),
            ("oracle_review", [good, edited], [review(True)]),
            ("oracle_review", [good, good, good], [review(continue_review=True), review()]),
            ("oracle_review", [good, bad], [review()]),
            ("oracle_review", [bad], []),
            ("oracle_review", [good] * 4, [{"exit_status": "Submitted", "submission": "bad JSON"}] * 3),
            ("oracle_review", [good, good], [{"exit_status": "model_call_limit", "submission": ""}]),
        ]
        for method, candidates, outcomes in cases:
            with self.subTest(method=method, outcomes=outcomes):
                self.assertEqual(self.run_case(original, method, candidates, outcomes),
                                 self.run_case(controller, method, candidates, outcomes))

    def test_verified_controller_decisions_are_preserved(self):
        good = Candidate("original", ["tests/a.py"], True, "captured")
        edited = Candidate("edited", ["tests/a.py"], True, "captured")
        mutated = Candidate("validation changed files", ["tests/a.py"], True, "captured")
        cases = [([good, good], [review()]),
                 ([good, edited, edited], [review(True)]),
                 ([good] * 4, [review(True)] * 3),
                 ([good, edited, mutated], [review(True)]),
                 ([good, good], [{"exit_status": "model_call_limit", "submission": ""}])]
        for candidates, outcomes in cases:
            with self.subTest(outcomes=outcomes):
                self.assertEqual(self.run_case(verified, "oracle_review", candidates, outcomes),
                                 self.run_case(controller, "verified_review", candidates, outcomes))

    def test_evidence_first_does_not_start_a_reviewer(self):
        good = Candidate("test patch", ["tests/a.py"], True, "captured")
        self.assertEqual(self.run_case(controller, "baseline", [good], []),
                         self.run_case(controller, "evidence_first", [good], []))

    def test_batch_plans_every_method_for_every_instance(self):
        jobs = make_jobs({"instances": [{"instance_id": "easy", "stratum": "easy"},
                                         {"instance_id": "hard", "stratum": "hard"}]},
                         ["baseline", "oracle_review", "verified_review", "evidence_first"])
        self.assertEqual(len(jobs), 8)
        self.assertEqual(jobs[0]["method"], "baseline")
        self.assertEqual(jobs[4]["method"], "evidence_first")


if __name__ == "__main__":
    unittest.main()
