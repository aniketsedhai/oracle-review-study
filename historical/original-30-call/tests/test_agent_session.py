"""Framework-adapter checks; run with the existing pilot virtual environment."""

import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT.parent / "mini-swe-agent/src"))
os.environ.setdefault("MSWEA_SILENT_STARTUP", "1")
os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"
runtime_config = tempfile.TemporaryDirectory(prefix="oracle-framework-test-")
os.environ["MSWEA_GLOBAL_CONFIG_DIR"] = runtime_config.name
try:
    from agent_session import AgentSession
    from minisweagent.exceptions import Submitted
except ImportError:
    AgentSession = None

from budget import Limits, SharedBudget


class FakeModel:
    def format_message(self, **kwargs):
        return kwargs

    def get_template_vars(self):
        return {}

    def serialize(self):
        return {}

    def query(self, messages):
        return {"role": "assistant", "content": "", "tool_calls": [
            {"id": "call", "type": "function", "function": {"name": "bash", "arguments": "{}"}}],
            "extra": {"cost": .01, "actions": [{"command": "submit"}]}}

    def format_observation_messages(self, message, outputs, variables):
        return [{"role": "tool", "tool_call_id": "call", "content": outputs[0]["output"]}]


class FakeEnvironment:
    def execute(self, action):
        raise Submitted({"role": "exit", "extra": {"exit_status": "Submitted", "submission": "{}"}})

    def serialize(self):
        return {}

    def get_template_vars(self):
        return {}


@unittest.skipIf(AgentSession is None, "Requires pilot virtual environment dependencies")
class SessionTests(unittest.TestCase):
    def test_round_continuation_retains_tool_observation_and_shared_usage(self):
        with tempfile.TemporaryDirectory() as directory:
            budget = SharedBudget(Limits(30, 1, 600))
            session = AgentSession(model=FakeModel(), env=FakeEnvironment(), task="review",
                                   budget=budget, phase_limits=budget.remaining(),
                                   output_directory=Path(directory), system_template="Reviewer")
            self.assertEqual(session.run_until_submission()["exit_status"], "Submitted")
            self.assertEqual(session.agent.messages[-1]["role"], "tool")
            session.continue_with("Review again")
            self.assertEqual(session.run_until_submission()["exit_status"], "Submitted")
            self.assertEqual(budget.model_calls, 2)
            self.assertAlmostEqual(budget.estimated_cost_usd, .02)


if __name__ == "__main__":
    unittest.main()
