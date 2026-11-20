from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from docker_startup import ensure_docker_ready


class DockerStartupTests(unittest.TestCase):
    @patch("docker_startup.subprocess.run")
    def test_ready_engine_does_not_open_app(self, run):
        run.return_value = SimpleNamespace(returncode=0)
        ensure_docker_ready()
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], "docker")

    @patch.dict("os.environ", {"DOCKER_HOST": ""})
    @patch("docker_startup.platform.system", return_value="Darwin")
    @patch("docker_startup.subprocess.run")
    def test_mac_starts_desktop_then_checks_engine(self, run, system):
        run.side_effect = [SimpleNamespace(returncode=1), SimpleNamespace(returncode=0),
                           SimpleNamespace(returncode=0)]
        ensure_docker_ready()
        self.assertEqual(run.call_args_list[1].args[0], ["open", "-a", "Docker"])
        self.assertEqual(run.call_count, 3)

    @patch("docker_startup.subprocess.run")
    def test_opt_out_never_opens_app(self, run):
        run.return_value = SimpleNamespace(returncode=1)
        with self.assertRaises(RuntimeError):
            ensure_docker_ready(auto_start=False)
        self.assertEqual(run.call_count, 1)

    @patch("docker_startup.subprocess.run", side_effect=FileNotFoundError)
    def test_missing_cli_gives_actionable_error(self, run):
        with self.assertRaisesRegex(RuntimeError, "CLI not found"):
            ensure_docker_ready()

    @patch.dict("os.environ", {"DOCKER_HOST": ""})
    @patch("docker_startup.platform.system", return_value="Darwin")
    @patch("docker_startup.time.sleep")
    @patch("docker_startup.time.monotonic", side_effect=[0, 0, 0, 2])
    @patch("docker_startup.subprocess.run")
    def test_engine_timeout_is_bounded(self, run, monotonic, sleep, system):
        run.side_effect = [SimpleNamespace(returncode=1), SimpleNamespace(returncode=0)]
        with self.assertRaisesRegex(RuntimeError, "did not become ready"):
            ensure_docker_ready(timeout=1)


if __name__ == "__main__":
    unittest.main()
