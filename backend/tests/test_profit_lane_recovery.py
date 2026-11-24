"""Selective comeback tests. Never infer earnings from a winning sample."""
import datetime as dt
import unittest

from backend.forward_edge_circuit import review, lane_recovery
from backend.paper_bot import assess_decision
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def row(action, setup, regime, net, minutes_ago):
    at = NOW - dt.timedelta(minutes=minutes_ago + 65)
    measured = NOW - dt.timedelta(minutes=minutes_ago)
    return {"action": action, "setup": setup, "regime": regime,
            "netReturnPct": net,
            "at": at.isoformat(), "measuredAt": measured.isoformat()}


class SelectiveRecoveryTests(unittest.TestCase):
    def test_only_positive_recent_bull_breakout_can_reopen_half_size(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        mark = quotes["BTCUSDT"]["priceTry"]
        state["micro"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(),
            "prices": [mark * (.976 + i * .0004) for i in range(60)],
        }
        # Some correlated market regimes underperform, but a specifically
        # measured bull breakout lane has recently improved with multiple
        # independent scan timestamps. The broad direction stays negative.
        state["forwardEvidence"]["completed"] = (
            [row("BUY", "breakout", "YÜKSELİŞ", -1.2,
                 150 - 3 * i) for i in range(12)]
            + [row("BUY", "breakout", "YÜKSELİŞ", .85,
                   105 - 3 * i) for i in range(12)]
            + [row("BUY", "trend", "YÜKSELİŞ", -1.1,
                   60 - 2 * i) for i in range(18)]
        )
        self.assertTrue(review(state, "BUY")["blocked"])
        lane = lane_recovery(state, "BUY", "breakout", "YÜKSELİŞ", NOW)
        self.assertTrue(lane["qualified"])
        self.assertEqual(lane["sizeMultiplier"], .5)
        self.assertTrue(lane["recentlyMeasured"])
        planned = assess_decision(state, quotes, NOW)
        self.assertEqual(planned["action"], "BUY")
        self.assertEqual(planned["symbol"], "BTCUSDT")
        self.assertLessEqual(planned["amountTry"], 40)
        self.assertEqual(state["trades"], [])  # plan not a filled order

    def test_bad_latest_six_cannot_cherry_pick_last_twelve(self):
        state, _ = market_prices([100 + i*.4 for i in range(168)])
        values = [-1.] * 12 + [2.] * 6 + [-.8] * 6
        state["forwardEvidence"]["completed"] = [
            row("BUY", "breakout", "YÜKSELİŞ", v,
                92 - 3 * i) for i, v in enumerate(values)]
        lane = lane_recovery(state, "BUY", "breakout", "YÜKSELİŞ", NOW)
        self.assertFalse(lane["qualified"])
        self.assertLess(lane["recent6AvgNetPct"], 0)

    def test_stale_lane_or_duplicate_scans_cannot_unlock(self):
        state, _ = market_prices([100 + i*.4 for i in range(168)])
        rows = [row("BUY", "breakout", "YÜKSELİŞ", .8, 600)
                for _ in range(24)]
        state["forwardEvidence"]["completed"] = rows
        check = lane_recovery(state, "BUY", "breakout", "YÜKSELİŞ", NOW)
        self.assertFalse(check["qualified"])
        self.assertFalse(check["recentlyMeasured"])
        self.assertEqual(check["distinctScanTimes12"], 1)

    def test_winning_short_not_allowed_to_bypass_negative_short_circuit(self):
        state, _ = market_prices([100 + i*.4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            row("SHORT", "breakdown", "YATAY", .7,
                90 - 2 * i) for i in range(24)]
        lane = lane_recovery(state, "SHORT", "breakdown", "YATAY", NOW)
        self.assertFalse(lane["qualified"])
        self.assertEqual(lane["sizeMultiplier"], 0)

    def test_missing_timestamps_fail_closed_even_when_numbers_positive(self):
        state, _ = market_prices([100 + i*.4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "setup": "breakout",
             "regime": "YÜKSELİŞ", "netReturnPct": 1.2}
            for _ in range(24)]
        self.assertFalse(lane_recovery(
            state, "BUY", "breakout", "YÜKSELİŞ", NOW)["qualified"])


if __name__ == "__main__":
    unittest.main()
