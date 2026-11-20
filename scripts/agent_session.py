"""Adapter to the existing mini-swe-agent classes; no framework files are edited.

Import this after adding the framework's src directory to sys.path. Environment
and model construction remain the launcher's responsibility.
"""

from minisweagent.agents.default import DefaultAgent
from minisweagent.exceptions import FormatError, InterruptAgentFlow, Submitted


class AgentSession:
    """Drive DefaultAgent.step without resetting history between review rounds.

    Limits are checked between steps. The launcher supplies deadline-aware
    environment/model wrappers and conservative pre-request cost estimates.
    Actual usage is recorded even if a request exceeds its estimate.
    """

    def __init__(self, *, model, env, task, budget, phase_limits,
                 output_directory, system_template, instance_template="{{task}}", role="generator"):
        self.budget = budget
        self.phase_limits = phase_limits
        self.initial_calls = budget.model_calls
        self.initial_cost = budget.estimated_cost_usd
        self.started = budget.clock()
        self.role = role
        self.limit_reminder_sent = False
        self.output_path = output_directory / "trajectory.json"
        self.agent = DefaultAgent(model, env, system_template=system_template,
                                  instance_template=instance_template,
                                  step_limit=0, cost_limit=0, wall_time_limit_seconds=0)
        self.agent.extra_template_vars = {"task": task}
        self.agent.add_messages(
            model.format_message(role="system", content=self.agent._render_template(system_template)),
            model.format_message(role="user", content=self.agent._render_template(instance_template)))

    def continue_with(self, task):
        # The terminal submission is a controller event, not an API conversation role.
        if self.agent.messages and self.agent.messages[-1].get("role") == "exit":
            self.agent.messages.pop()
        self.agent.add_messages(self.agent.model.format_message(role="user", content=task))

    def stop_reason(self):
        reason = self.budget.stop_reason()
        if reason:
            return reason
        if self.budget.model_calls - self.initial_calls >= self.phase_limits.model_calls:
            return "phase_model_call_limit"
        if self.budget.estimated_cost_usd - self.initial_cost >= self.phase_limits.estimated_cost_usd:
            return "phase_estimated_cost_limit"
        if self.budget.clock() - self.started >= self.phase_limits.seconds:
            return "phase_wall_time_limit"
        return None

    def run_until_submission(self):
        while True:
            reason = self.stop_reason()
            if reason:
                self.agent.save(self.output_path)
                return {"exit_status": reason, "submission": ""}
            previous_calls = self.agent.n_calls
            previous_cost = self.agent.cost
            calls_left = min(self.budget.remaining().model_calls,
                             self.phase_limits.model_calls - (self.budget.model_calls - self.initial_calls))
            if calls_left <= 2 and not self.limit_reminder_sent:
                if self.role == "reviewer":
                    instruction = "Submit the required JSON review record now using the completion marker. "
                else:
                    instruction = "Preserve your best current test changes and submit using the completion marker now. "
                self.agent.add_messages(self.agent.model.format_message(
                    role="user", content=f"Only {calls_left} model calls remain in this phase. "
                    + instruction + "Avoid further exploration or optional edits."))
                self.limit_reminder_sent = True
            outcome = None
            try:
                outcome = self._step()
                self.agent.n_consecutive_format_errors = 0
            except FormatError as error:
                self.agent.cost += error.messages[0].get("extra", {}).get("cost", 0.0)
                self.agent.add_messages(*error.messages)
                self.agent.n_consecutive_format_errors += 1
                if self.agent.n_consecutive_format_errors >= 3:
                    outcome = {"exit_status": "RepeatedFormatError", "submission": ""}
            except InterruptAgentFlow as error:
                self.agent.add_messages(*error.messages)
                if self.agent.messages[-1].get("role") == "exit":
                    outcome = self.agent.messages[-1].get("extra", {})
            except Exception as error:
                # Do not persist exception text that may include request secrets.
                outcome = {"exit_status": type(error).__name__, "submission": ""}
            finally:
                self.budget.charge(self.agent.n_calls - previous_calls,
                                   self.agent.cost - previous_cost)
                self.agent.save(self.output_path)
            if outcome is not None:
                return outcome

    def _step(self):
        message = self.agent.query()
        outputs = []
        submission = None
        for action in message.get("extra", {}).get("actions", []):
            try:
                outputs.append(self.agent.env.execute(action))
            except Submitted as event:
                submission = event.messages[-1].get("extra", {})
                outputs.append({"output": "Round submitted to controller.",
                                "returncode": 0, "exception_info": ""})
        # A submitted round still needs matching tool responses. Otherwise the
        # next reviewer round would send an invalid tool-call conversation.
        self.agent.add_messages(*self.agent.model.format_observation_messages(
            message, outputs, self.agent.get_template_vars()))
        return submission
