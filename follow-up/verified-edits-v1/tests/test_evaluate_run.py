import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from evaluate_run import prepare_inputs


class EvaluationInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / "generation"
        self.run.mkdir()
        self.instance = {"instance_id": "example", "base_commit": "a" * 40,
                         "dataset": "example/data", "dataset_revision": "revision"}
        (self.run / "instance.json").write_text(json.dumps(self.instance))
        (self.run / "prediction.patch").write_text("patch")
        (self.run / "predictions.jsonl").write_text(json.dumps(
            {"instance_id": "example", "model_patch": "patch"}) + "\n")
        self.provenance = {"dataset": "example/data", "dataset_revision": "revision"}

    def test_reference_inputs_remain_separate_and_prediction_is_identical(self):
        output = self.root / "evaluation"
        prepare_inputs(self.run, [self.instance], self.provenance, output)
        self.assertEqual((output / "predictions-frozen.jsonl").read_bytes(),
                         (self.run / "predictions.jsonl").read_bytes())
        self.assertFalse((self.run / "instance-evaluator-only.json").exists())

    def test_wrong_revision_rejected(self):
        with self.assertRaises(ValueError):
            prepare_inputs(self.run, [self.instance], dict(self.provenance, dataset_revision="other"),
                           self.root / "evaluation")

    def test_mismatched_frozen_patch_rejected(self):
        (self.run / "prediction.patch").write_text("different")
        with self.assertRaises(ValueError):
            prepare_inputs(self.run, [self.instance], self.provenance, self.root / "evaluation")


if __name__ == "__main__":
    unittest.main()
