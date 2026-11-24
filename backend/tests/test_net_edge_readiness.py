"""Economic entry gate tests using only *later observed* research prices."""
import datetime as dt
import unittest

from backend.net_edge_readiness import review, snapshot
from backend.paper_bot import assess_decision, execute, fresh_state
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def observed(side, result, index, symbol=None, hours_old=0):
    measured = NOW - dt.timedelta(minutes=max(1, 90-index)+hours_old*60)
    started = measured - dt.timedelta(minutes=62)
    return {
        "action": side, "netReturnPct": result,
        "symbol": symbol or f"TOKEN{index%12}USDT",
        "at": started.isoformat(), "measuredAt": measured.isoformat(),
        "regime": "YÜKSELİŞ", "setup": "breakout",
    }


class NetEdgeReadinessTests(unittest.TestCase):
    def test_negative_live_spot_evidence_pauses_new_buys_not_research(self):
        state, quotes = market_prices([100 + i*.4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            observed("BUY", -.45, i) for i in range(60)]
        gate = review(state, "BUY", NOW)
        self.assertEqual(gate["status"], "NO_PROVEN_NET_EDGE")
        self.assertTrue(gate["blocked"])
        self.assertLess(gate["last60AvgNetPct"], 0)
        plan = assess_decision(state, quotes, NOW)
        research = assess_decision(state, quotes, NOW, research_only=True)
        self.assertEqual(plan["action"], "WAIT")
        self.assertTrue(plan["netEdgeReadiness"]["BUY"]["blocked"])
        # Per-setup risk veto may reject this symbol first; the independent
        # economic gate still reports the failing overall net return.
        self.assertTrue(plan["rejectReasons"])
        self.assertEqual(plan["netEdgeReadiness"]["BUY"]["status"],
                         "NO_PROVEN_NET_EDGE")
        self.assertTrue(any(row["symbol"] == "BTCUSDT"
                            for row in research["candidates"]))
        self.assertIsNone(research["order"])
        self.assertEqual(state["trades"], [])

    def test_latest_short_streak_cannot_overrule_losing_sixty(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = (
            [observed("SHORT", -1.0, i) for i in range(36)]
            + [observed("SHORT", .32, i+36) for i in range(24)])
        result = review(state, "SHORT", NOW)
        self.assertTrue(result["blocked"])
        self.assertGreater(result["last24AvgNetPct"], .2)
        self.assertLess(result["last60AvgNetPct"], 0)
        self.assertEqual(result["last24Positive"], 24)

    def test_fresh_diverse_net_positive_both_windows_is_provisional_not_profit(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            observed("BUY", .45, i) for i in range(60)]
        result = review(state, "BUY", NOW)
        self.assertFalse(result["blocked"])
        self.assertEqual(result["status"], "PROVISIONAL_REVALIDATION")
        self.assertTrue(result["provisionallyRevalidated"])
        self.assertFalse(review(state, "SHORT", NOW)["blocked"])
        self.assertTrue(snapshot(state, NOW)["notAProfitForecast"])

    def test_stale_or_single_coin_prevents_fake_revalidation(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            observed("BUY", .50, i, hours_old=7) for i in range(60)]
        self.assertTrue(review(state, "BUY", NOW)["blocked"])
        state["forwardEvidence"]["completed"] = [
            observed("BUY", .50, i, symbol="ONEUSDT") for i in range(60)]
        result = review(state, "BUY", NOW)
        self.assertTrue(result["blocked"])
        self.assertEqual(result["distinctSymbols"], 1)

    def test_open_position_protective_exit_ignores_entry_readiness(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            observed("BUY", -.75, i) for i in range(60)]
        execute(state, NOW-dt.timedelta(hours=2), "BTCUSDT", "buy",
                55, 100, "old paper spot")
        planned = assess_decision(
            state, {"BTCUSDT": {"priceTry": 94, "entryEligible": False}},
            NOW, exits_only=True, price_only=True)
        self.assertTrue(planned["netEdgeReadiness"]["BUY"]["blocked"])
        self.assertEqual(planned["action"], "SELL")
        self.assertIn("BTCUSDT", state["holdings"])
        self.assertEqual(len(state["trades"]), 1)

    def test_initial_paper_lab_can_collect_before_evidence_threshold(self):
        state = fresh_state()
        self.assertFalse(review(state, "BUY", NOW)["blocked"])
        state["forwardEvidence"]["completed"] = [
            observed("BUY", -.5, i) for i in range(29)]
        self.assertFalse(review(state, "BUY", NOW)["blocked"])
        state["forwardEvidence"]["completed"].append(
            observed("BUY", -.5, 29))
        self.assertTrue(review(state, "BUY", NOW)["blocked"])


if __name__ == "__main__":
    unittest.main()
