"""No-profit-fabrication regression tests for exit learning and research."""
import datetime as dt
import unittest

from backend.paper_bot import assess_decision, execute, fresh_state
from backend.risk_feedback import (
    broad_risk_on, loss_reentry_cooldown, position_monitor,
    short_reversal_exit, short_size_multiplier, spot_trend_failure_exit,
)
from backend.short_positions import open_short
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def descending_fast(mark):
    return [mark * (1.1235 - i*.0013) for i in range(96)]


def rising_fast(mark):
    return [mark * (.905 + i*.001) for i in range(96)]


def descending_micro(mark):
    return [mark * (1.024 - i*.0004) for i in range(60)]


def rising_micro(mark):
    return [mark * (.976 + i*.0004) for i in range(60)]


class RiskFeedbackTests(unittest.TestCase):
    def test_broad_up_market_requires_bitcoin_up_and_actual_breadth(self):
        self.assertTrue(broad_risk_on({"tracked": 50, "up": 41}, "up"))
        self.assertFalse(broad_risk_on({"tracked": 50, "up": 41}, "down"))
        self.assertFalse(broad_risk_on({"tracked": 50, "up": 29}, "up"))
        self.assertFalse(broad_risk_on({"tracked": 5, "up": 5}, "up"))

    def test_short_size_is_reduced_by_actual_forward_losses_without_zeroing(self):
        state = fresh_state()
        self.assertEqual(short_size_multiplier(state), .75)
        state["forwardEvidence"]["completed"] = [
            {"action": "SHORT", "netReturnPct": -2} for _ in range(6)]
        self.assertEqual(short_size_multiplier(state), .5)
        state["forwardEvidence"]["completed"].append({
            "action": "SHORT", "netReturnPct": 1})
        self.assertEqual(short_size_multiplier(state), .75)

    def test_short_reversal_requires_multiple_fresh_confirmations(self):
        fast = {"momentum1h": .55, "momentum4h": 1.1}
        micro = {"momentum15": .65}
        breadth = {"tracked": 50, "up": 42}
        self.assertTrue(short_reversal_exit(3700, .026, fast, micro,
                                             breadth, "YÜKSELİŞ"))
        self.assertFalse(short_reversal_exit(200, .026, fast, micro,
                                              breadth, "YÜKSELİŞ"))
        self.assertFalse(short_reversal_exit(3700, .026, fast, micro,
                                              breadth, "DÜŞÜŞ"))
        self.assertFalse(short_reversal_exit(3700, .026, fast, None,
                                              breadth, "YÜKSELİŞ"))
        self.assertFalse(short_reversal_exit(3700, .026, fast, micro,
                                              {"tracked": 50, "up": 15},
                                              "YÜKSELİŞ"))

    def test_spot_stalling_exit_needs_two_hours_and_three_confirmations(self):
        fast = {"momentum1h": -.6, "momentum4h": -1.6}
        micro = {"momentum15": -.8}
        tech = {"direction": "down", "score": -.9}
        self.assertTrue(spot_trend_failure_exit(9000, -.012, fast, micro, tech))
        self.assertFalse(spot_trend_failure_exit(1800, -.012, fast, micro, tech))
        self.assertFalse(spot_trend_failure_exit(9000, -.003, fast, micro, tech))
        self.assertFalse(spot_trend_failure_exit(9000, -.012, fast, None, tech))
        self.assertFalse(spot_trend_failure_exit(
            9000, -.012, fast, micro, {"direction": "up", "score": .9}))

    def test_recent_realized_loss_blocks_reentry_but_not_win(self):
        state = fresh_state()
        state["trades"] = [{
            "symbol": "ETHUSDT", "side": "sell",
            "realizedPnlTry": -.5,
            "at": (NOW - dt.timedelta(minutes=20)).isoformat(),
        }]
        self.assertTrue(loss_reentry_cooldown(state, "ETHUSDT", NOW))
        self.assertFalse(loss_reentry_cooldown(
            state, "ETHUSDT", NOW + dt.timedelta(minutes=92)))
        self.assertFalse(loss_reentry_cooldown(state, "BTCUSDT", NOW))
        state["trades"][0]["realizedPnlTry"] = .1
        self.assertFalse(loss_reentry_cooldown(state, "ETHUSDT", NOW))

    def test_live_bullish_breadth_short_reversal_closes_previously_held_short(self):
        state, latest = market_prices([100 + i*.4 for i in range(168)])
        mark = latest["BTCUSDT"]["priceTry"]
        open_short(state, NOW - dt.timedelta(hours=2),
                   "BTCUSDT", 60, mark/1.02, "preexisting paper short")
        state["marketPulse"] = {"tracked": 50, "up": 40}
        state["intraday"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": rising_fast(mark)}
        state["micro"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": rising_micro(mark)}
        plan = assess_decision(state, latest, NOW)
        self.assertEqual(plan["action"], "COVER")
        self.assertIn("rejim tersine döndü", plan["reason"])
        self.assertEqual(len(state["shorts"]), 1)  # planning never executes
        self.assertEqual(len(state["trades"]), 1)

    def test_trend_broken_spot_exits_after_two_hours_without_hard_stop(self):
        state, latest = market_prices([200 - i*.35 for i in range(168)])
        mark = latest["BTCUSDT"]["priceTry"]
        execute(state, NOW - dt.timedelta(hours=3),
                "BTCUSDT", "buy", 60, mark/0.985, "preexisting paper long")
        state["intraday"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": descending_fast(mark)}
        state["micro"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": descending_micro(mark)}
        plan = assess_decision(state, latest, NOW)
        self.assertEqual(plan["action"], "SELL")
        self.assertIn("trend bozulması", plan["reason"])
        self.assertEqual(len(state["holdings"]), 1)

    def test_research_still_sees_signals_while_live_wallet_is_full(self):
        state, latest = market_prices([100 + i*.4 for i in range(168)])
        state["cashTry"] = 130
        state["holdings"]["ETHUSDT"] = {"quantity": 5, "costTry": 500}
        latest["ETHUSDT"] = {"priceTry": 100}
        real = assess_decision(state, latest, NOW)
        probe = assess_decision(state, latest, NOW, research_only=True)
        self.assertEqual(real["action"], "WAIT")
        self.assertEqual(probe["action"], "WAIT")
        self.assertTrue(any(row["symbol"] == "BTCUSDT" for row in probe["candidates"]))
        self.assertIsNone(probe["order"])
        self.assertEqual(state["cashTry"], 130)
        self.assertEqual(len(state["holdings"]), 1)

    def test_estimated_exit_pnl_is_observed_mark_after_both_spot_fees(self):
        state, latest = market_prices([100 + i*.4 for i in range(168)])
        mark = latest["BTCUSDT"]["priceTry"]
        execute(state, NOW - dt.timedelta(hours=2),
                "BTCUSDT", "buy", 50, mark, "known paper long")
        rows = position_monitor(state, latest, NOW)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["side"], "SPOT")
        self.assertLess(rows[0]["estimatedCloseNetTry"], 0)
        self.assertEqual(len(state["trades"]), 1)


if __name__ == "__main__":
    unittest.main()
