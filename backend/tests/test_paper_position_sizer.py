"""Paper order sizing constraints, independent of future profit claims."""
import unittest

from backend.paper_position_sizer import size_trial, MODEL_ADVERSE_PCT
from backend.paper_bot import fresh_state


def trial(state, latest=None, **opts):
    return size_trial(
        state, latest if latest is not None else {},
        equity=opts.get("equity", 650),
        exposure=opts.get("exposure", 0),
        volatility=opts.get("volatility", 4.5),
        cash_reserve_pct=.20,
        exposure_ceiling_pct=.78,
        entry_fee=.001,
    )


class PaperPositionSizerTests(unittest.TestCase):
    def test_good_breakout_can_use_more_budget_without_unlimited_risk(self):
        state = fresh_state()
        s = trial(state)
        self.assertTrue(s["approved"])
        self.assertEqual(s["mode"], "QUALIFIED_SPOT_BREAKOUT_RISK_BUDGET")
        self.assertAlmostEqual(s["amountTry"], 117.0, places=2)
        self.assertLessEqual(s["estimatedLossAtStopTry"], 650*.006)
        self.assertEqual(s["maxPerPositionPct"], 18.0)
        self.assertEqual(s["maxGroupPct"], 25.0)
        self.assertTrue(s["scenarioNotGuaranteed"])
        self.assertAlmostEqual(MODEL_ADVERSE_PCT, .031)

    def test_high_volatility_reduces_ticket_not_enlarges_it(self):
        low = trial(fresh_state(), volatility=5)
        high = trial(fresh_state(), volatility=7)
        self.assertLess(high["amountTry"], low["amountTry"])
        self.assertAlmostEqual(high["amountTry"], 76.05)

    def test_existing_breakout_group_caps_next_trial(self):
        state = fresh_state()
        state["openSignals"] = {
            "BTCUSDT": {"side": "buy", "setup": "breakout"},
            "ETHUSDT": {"side": "buy", "setup": "breakout"},
        }
        state["holdings"] = {
            "BTCUSDT": {"quantity": 1, "costTry": 70},
            "ETHUSDT": {"quantity": 1, "costTry": 70},
        }
        latest = {"BTCUSDT": {"priceTry": 70},
                  "ETHUSDT": {"priceTry": 70}}
        result = trial(state, latest, exposure=140)
        self.assertAlmostEqual(result["amountTry"], 22.5)
        self.assertEqual(result["breakoutAlreadyOpenTry"], 140.0)
        self.assertLessEqual(result["amountTry"] + 140, 650*.25)
        self.assertEqual(len(state["holdings"]), 2)

    def test_missing_open_breakout_quote_blocks_instead_of_guessing(self):
        s = fresh_state()
        s["openSignals"]["BTCUSDT"] = {
            "side": "buy", "setup": "breakout"}
        s["holdings"]["BTCUSDT"] = {"quantity": 1, "costTry": 70}
        result = trial(s, {})
        self.assertFalse(result["approved"])
        self.assertEqual(result["amountTry"], 0.0)
        self.assertIn("fiyatı eksik", result["reason"])

    def test_cash_and_total_exposure_reserve_never_bypassed(self):
        s = fresh_state()
        s["cashTry"] = 150
        result = trial(s, exposure=495)
        self.assertLess(result["amountTry"], 11)
        self.assertGreaterEqual(result["amountTry"], 5)
        self.assertLessEqual(
            result["amountTry"], (150-130)/1.001)
        s["cashTry"] = 120
        rejected = trial(s, exposure=495)
        self.assertFalse(rejected["approved"])
        self.assertEqual(rejected["amountTry"], 0)

    def test_invalid_money_and_nan_fail_closed(self):
        s = fresh_state()
        for invalid in (float("nan"), -1, 0):
            r = trial(s, equity=invalid)
            self.assertFalse(r["approved"])
            self.assertEqual(r["amountTry"], 0)
        s["cashTry"] = "unverified"
        self.assertFalse(trial(s)["approved"])


if __name__ == "__main__":
    unittest.main()
