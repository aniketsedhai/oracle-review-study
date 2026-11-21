"""Shared generation/review accounting, independent of the model framework."""

from dataclasses import dataclass
import math
import time
from typing import Callable


@dataclass(frozen=True)
class Limits:
    model_calls: int
    estimated_cost_usd: float
    seconds: float

    def __post_init__(self):
        if (not isinstance(self.model_calls, int) or self.model_calls < 0
                or not math.isfinite(self.estimated_cost_usd)
                or not math.isfinite(self.seconds)
                or self.estimated_cost_usd < 0 or self.seconds < 0):
            raise ValueError("Limits must be finite and nonnegative, with integer calls")


class SharedBudget:
    """One ledger per method/instance; start immediately before generation.

    Elapsed wall time includes checkpointing and transitions after the start.
    Environment setup before the start and official evaluation are separate.
    Call and token-cost usage must be charged even after failed/invalid responses.
    Cost is an accounting estimate, not a provider invoice or prepaid reservation.
    """

    def __init__(self, limits: Limits, clock: Callable[[], float] = time.monotonic):
        self.limits = limits
        self.clock = clock
        self.started = clock()
        self.model_calls = 0
        self.estimated_cost_usd = 0.0

    def charge(self, model_calls: int, estimated_cost_usd: float) -> None:
        # Validate deltas before changing either counter.
        Limits(model_calls, estimated_cost_usd, 0)
        self.model_calls += model_calls
        self.estimated_cost_usd += estimated_cost_usd

    def remaining(self) -> Limits:
        return Limits(
            max(0, self.limits.model_calls - self.model_calls),
            max(0.0, self.limits.estimated_cost_usd - self.estimated_cost_usd),
            max(0.0, self.limits.seconds - (self.clock() - self.started)),
        )

    def allowance(self, phase_cap: Limits | None = None) -> Limits:
        remaining = self.remaining()
        if phase_cap is None:
            return remaining
        return Limits(
            min(remaining.model_calls, phase_cap.model_calls),
            min(remaining.estimated_cost_usd, phase_cap.estimated_cost_usd),
            min(remaining.seconds, phase_cap.seconds),
        )

    def stop_reason(self) -> str | None:
        remaining = self.remaining()
        if remaining.model_calls == 0:
            return "model_call_limit"
        if remaining.estimated_cost_usd == 0:
            return "estimated_cost_limit"
        if remaining.seconds == 0:
            return "wall_time_limit"
        return None

    def snapshot(self) -> dict:
        return {
            "model_calls": self.model_calls,
            "estimated_cost_usd": self.estimated_cost_usd,
            "elapsed_seconds": self.clock() - self.started,
            "stop_reason": self.stop_reason(),
        }
