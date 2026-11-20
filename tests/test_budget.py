import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from budget import Limits, SharedBudget


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.now = 100.0
        self.budget = SharedBudget(Limits(30, 1.0, 600), clock=lambda: self.now)

    def test_generation_cap_reserves_review_capacity(self):
        allowance = self.budget.allowance(Limits(20, 0.6, 360))
        self.assertEqual(allowance, Limits(20, 0.6, 360))
        self.budget.charge(20, 0.6)
        self.now += 360
        remaining = self.budget.remaining()
        self.assertEqual(remaining.model_calls, 10)
        self.assertAlmostEqual(remaining.estimated_cost_usd, 0.4)
        self.assertEqual(remaining.seconds, 240)

    def test_unused_generation_allowance_carries_into_review(self):
        self.budget.charge(8, 0.012)
        self.now += 20
        remaining = self.budget.allowance()
        self.assertEqual(remaining.model_calls, 22)
        self.assertAlmostEqual(remaining.estimated_cost_usd, 0.988)
        self.assertEqual(remaining.seconds, 580)

    def test_review_usage_accumulates_in_same_ledger(self):
        self.budget.charge(20, 0.6)
        self.budget.charge(10, 0.2)
        self.assertEqual(self.budget.stop_reason(), "model_call_limit")

    def test_time_expires_even_without_model_calls(self):
        self.now += 601
        self.assertEqual(self.budget.stop_reason(), "wall_time_limit")
        self.assertEqual(self.budget.remaining().seconds, 0)

    def test_cost_overrun_is_recorded_not_hidden(self):
        self.budget.charge(1, 1.01)
        self.assertEqual(self.budget.stop_reason(), "estimated_cost_limit")
        self.assertEqual(self.budget.snapshot()["estimated_cost_usd"], 1.01)

    def test_bad_usage_does_not_modify_ledger(self):
        with self.assertRaises(ValueError):
            self.budget.charge(1, float("nan"))
        self.assertEqual(self.budget.model_calls, 0)


if __name__ == "__main__":
    unittest.main()
