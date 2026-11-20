"""Deadline and request-estimate guards around the existing model/environment."""

import json

from minisweagent.models.litellm_model import LitellmModel


class RequestBudgetUnavailable(RuntimeError):
    pass


class PhaseAllowance:
    def __init__(self, budget, limits):
        self.budget, self.limits = budget, limits
        self.started = budget.clock()
        self.initial_cost = budget.estimated_cost_usd

    def seconds(self):
        return max(0, min(self.budget.remaining().seconds,
                          self.limits.seconds - (self.budget.clock() - self.started)))

    def cost(self):
        return max(0, min(self.budget.remaining().estimated_cost_usd,
                          self.limits.estimated_cost_usd
                          - (self.budget.estimated_cost_usd - self.initial_cost)))


class DeadlineEnvironment:
    """Only wraps model-selected commands; checkpointing uses the original env."""
    def __init__(self, env, allowance):
        self.env, self.allowance = env, allowance

    def execute(self, action):
        seconds = min(self.env.config.timeout, self.allowance.seconds())
        if seconds <= 0:
            return {"output": "Command skipped: time allowance exhausted.",
                    "returncode": -1, "exception_info": "deadline"}
        return self.env.execute(action, timeout=seconds)

    def get_template_vars(self):
        return self.env.get_template_vars()

    def serialize(self):
        return self.env.serialize()


class GuardedModel(LitellmModel):
    """Conservative request estimates using configured rates, not invoice guarantees.

    Uses UTF-8 payload bytes plus a safety margin as an input-token estimate.
    Provider tokenization, tool overhead, and pricing can differ; record actual
    token usage and recheck provider pricing before running the study.
    """
    def __init__(self, *, allowance, input_usd_per_million, output_usd_per_million, **kwargs):
        super().__init__(**kwargs)
        self.allowance = allowance
        self.input_rate = input_usd_per_million
        self.output_rate = output_usd_per_million
        self.requests_started = 0

    def _query(self, messages, **kwargs):
        maximum_output = self.config.model_kwargs["max_tokens"]
        estimated_input = len(json.dumps(messages, ensure_ascii=False).encode()) + 8192
        reservation = (estimated_input * self.input_rate + maximum_output * self.output_rate) / 1_000_000
        if reservation > self.allowance.cost() or self.allowance.seconds() <= 0:
            raise RequestBudgetUnavailable("Insufficient allowance for estimated request")
        kwargs["timeout"] = max(.001, min(self.config.model_kwargs.get("timeout", 90),
                                          self.allowance.seconds()))
        self.requests_started += 1
        return super()._query(messages, **kwargs)

    def _calculate_cost(self, response):
        usage = response.usage
        return {"cost": (usage.prompt_tokens * self.input_rate
                         + usage.completion_tokens * self.output_rate) / 1_000_000}
