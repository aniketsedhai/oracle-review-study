import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from prepare_study import prepare
from test_layout import discover_test_roots
from run_batch import make_jobs


class PreparationTests(unittest.TestCase):
    def test_reference_answers_are_not_written_to_generation_inputs(self):
        selection = {"instances": [{"instance_id": "a", "stratum": "easy"}], "status": "proposed",
                     "source": "slides", "dataset": "dataset", "dataset_revision": "revision"}
        row = {"instance_id": "a", "repo": "owner/repo", "base_commit": "a" * 40,
               "problem_statement": "issue", "patch": "SECRET REFERENCE FIX", "test_patch": "GOLDEN TESTS"}
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "inputs"
            prepare(selection, [row], target)
            text = (target / "a.json").read_text()
            self.assertNotIn("SECRET REFERENCE FIX", text)
            self.assertNotIn("GOLDEN TESTS", text)

    def test_nested_test_layout_does_not_allow_entire_production_package(self):
        roots = discover_test_roots(["sympy/core/tests/test_numbers.py", "sympy/core/numbers.py",
                                     "sympy/matrices/tests/test_dense.py", "testing/test_cli.py"])
        self.assertEqual(roots, ["sympy/core/tests", "sympy/matrices/tests", "testing"])

    def test_batch_has_one_of_each_method_and_counterbalances_order(self):
        jobs = make_jobs({"instances": [
            {"instance_id": "easy", "stratum": "easy"},
            {"instance_id": "hard", "stratum": "hard"}]})
        self.assertEqual([(job["instance_id"], job["method"]) for job in jobs],
                         [("easy", "baseline"), ("easy", "oracle_review"),
                          ("hard", "oracle_review"), ("hard", "baseline")])


if __name__ == "__main__":
    unittest.main()
