"""Integration checks using real Git, without Docker, API keys, or model calls."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from patches import capture_candidate, check_forward_application
from controller import checkpoint_candidate


class LocalEnvironment:
    def __init__(self, root):
        self.root = root

    def execute(self, action):
        result = subprocess.run(action["command"], shell=True, cwd=self.root,
                                text=True, capture_output=True)
        return {"output": result.stdout, "returncode": result.returncode}


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = LocalEnvironment(self.root)
        (self.root / "tests").mkdir()
        (self.root / "tests/test_existing.py").write_text("assert True\n")
        (self.root / "source.py").write_text("value = 1\n")
        for args in (["init", "-q"], ["add", "."],
                     ["-c", "user.name=Test", "-c", "user.email=test@localhost",
                      "commit", "-qm", "base"]):
            subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def test_new_test_is_captured_and_applies_to_clean_base(self):
        (self.root / "tests/test_new.py").write_text("assert 1 == 1\n")
        candidate = capture_candidate(self.env, ["tests"])
        self.assertTrue(candidate.usable, candidate.reason)
        self.assertEqual(candidate.changed_paths, ["tests/test_new.py"])
        (self.root / "tests/test_new.py").unlink()
        result = subprocess.run(["git", "apply", "--check", "-"], cwd=self.root,
                                input=candidate.patch, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_production_change_invalidates_entire_candidate(self):
        (self.root / "source.py").write_text("value = 2\n")
        (self.root / "tests/test_new.py").write_text("assert True\n")
        candidate = capture_candidate(self.env, ["tests"])
        self.assertFalse(candidate.usable)
        self.assertEqual(candidate.reason, "disallowed_paths")
        self.assertEqual(candidate.patch, "")

    def test_no_changes_is_not_a_candidate(self):
        self.assertEqual(capture_candidate(self.env, ["tests"]).reason, "no_changes")

    def test_symlink_cannot_masquerade_as_python_test(self):
        (self.root / "tests/test_link.py").symlink_to("../source.py")
        self.assertFalse(capture_candidate(self.env, ["tests"]).usable)

    def test_binary_cannot_masquerade_as_python_test(self):
        (self.root / "tests/test_binary.py").write_bytes(b"\0\xff\0")
        self.assertEqual(capture_candidate(self.env, ["tests"]).reason, "binary_changes")

    def test_forward_check_rejects_wrong_base_without_changing_files(self):
        (self.root / "tests/test_existing.py").write_text("assert False\n")
        candidate = capture_candidate(self.env, ["tests"])
        self.assertTrue(candidate.usable)
        incompatible = candidate.patch.replace("-assert True", "-assert missing")
        self.assertNotEqual(check_forward_application(self.env, incompatible)["returncode"], 0)
        self.assertEqual((self.root / "tests/test_existing.py").read_text(), "assert False\n")

    def test_checkpoint_saves_record_and_does_not_overwrite(self):
        (self.root / "tests/test_new.py").write_text("assert True\n")
        directory = self.root / "checkpoint"
        candidate = checkpoint_candidate(self.env, ["tests"], directory)
        self.assertTrue(candidate.usable)
        self.assertEqual((directory / "candidate.patch").read_text(), candidate.patch)
        self.assertTrue((directory / "candidate.json").exists())
        with self.assertRaises(FileExistsError):
            checkpoint_candidate(self.env, ["tests"], directory)


if __name__ == "__main__":
    unittest.main()
