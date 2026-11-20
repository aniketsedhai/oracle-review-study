import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parents[2] / "mini-swe-agent/src"))
os.environ.setdefault("MSWEA_SILENT_STARTUP", "1")
os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"
runtime_config = tempfile.TemporaryDirectory(prefix="oracle-runtime-test-")
os.environ["MSWEA_GLOBAL_CONFIG_DIR"] = runtime_config.name
try:
    from runtime import DeadlineEnvironment, GuardedModel, PhaseAllowance, RequestBudgetUnavailable
except ImportError:
    GuardedModel = None
from budget import Limits, SharedBudget


@unittest.skipIf(GuardedModel is None, "Requires pilot virtual environment dependencies")
class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.budget = SharedBudget(Limits(30, 1, 600), clock=lambda: self.now)
        self.allowance = PhaseAllowance(self.budget, Limits(20, .6, 360))

    def model(self):
        return GuardedModel(allowance=self.allowance, input_usd_per_million=.3,
                            output_usd_per_million=1.2, model_name="deepseek/deepseek-flash",
                            model_kwargs={"max_tokens": 4096, "timeout": 90})

    def test_request_refused_before_provider_call_when_estimate_wont_fit(self):
        self.budget.charge(1, .5999)
        with patch("runtime.LitellmModel._query") as request:
            with self.assertRaises(RequestBudgetUnavailable):
                self.model()._query([{"role": "user", "content": "hello"}])
            request.assert_not_called()

    def test_request_timeout_clamped_to_remaining_phase_time(self):
        self.now = 355
        with patch("runtime.LitellmModel._query", return_value="response") as request:
            self.assertEqual(self.model()._query([]), "response")
            self.assertEqual(request.call_args.kwargs["timeout"], 5)

    def test_expired_command_is_not_executed(self):
        class Environment:
            config = SimpleNamespace(timeout=60)
            def execute(self, *args, **kwargs):
                raise AssertionError("Must not execute")
        self.now = 361
        result = DeadlineEnvironment(Environment(), self.allowance).execute({"command": "anything"})
        self.assertEqual(result["returncode"], -1)


if __name__ == "__main__":
    unittest.main()
