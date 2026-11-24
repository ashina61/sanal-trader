"""Only a bounded trial from actual filled winners AND later observed prices."""
import datetime as dt
import unittest

from backend.profit_first_policy import evaluate, historical_loss_guard
from backend.paper_bot import assess_decision, fresh_state
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def paper_stats(state):
    state["signalStats"] = {
        "spot:breakout": {"closed": 8, "wins": 8, "netTry": 11.454931,
                          "meanRoi": .0248125},
        "spot:trend": {"closed": 4, "wins": 1, "netTry": -7.65357,
                       "meanRoi": -.0269187},
        "short:breakdown": {"closed": 2, "wins": 0, "netTry": -5.164959,
                            "meanRoi": -.033533},
        "short:trend": {"closed": 1, "wins": 0, "netTry": -1.63803,
                        "meanRoi": -.028145},
    }


def sample(action, setup, regime, gain, index):
    # Synthetic test fixtures mimic genuine later observations separated
    # by at least one hour; neither sample nor validation is a wallet fill.
    measured = NOW - dt.timedelta(minutes=max(1, 30 - index))
    timestamp = measured - dt.timedelta(minutes=62)
    return {
        "action": action, "setup": setup, "regime": regime,
        "netReturnPct": gain, "at": timestamp.isoformat(),
        "measuredAt": measured.isoformat(), "symbol": f"COIN{index}USDT"
    }


def upside_probe_state():
    state = fresh_state()
    paper_stats(state)
    # Six genuinely different coins/scans, four positive net outcomes.
    positive = [.18, -.04, .19, .18, -.04, .22]
    state["forwardEvidence"]["completed"] = [
        sample("BUY", "breakout", "YATAY", v, i)
        for i, v in enumerate(positive)]
    return state


class ProfitFirstTests(unittest.TestCase):
    def test_closed_winning_spot_breakout_allows_half_size_trial(self):
        state = upside_probe_state()
        row = evaluate(state, "BUY", "breakout", "YATAY", NOW)
        self.assertTrue(row["qualified"])
        self.assertEqual(row["sizeMultiplier"], .50)
        self.assertEqual(row["realizedSpotBreakout"]["closed"], 8)
        self.assertEqual(row["realizedSpotBreakout"]["wins"], 8)
        self.assertGreater(row["forwardSidewaysBreakout"]["recentAvgNetPct"], .10)
        self.assertFalse(evaluate(state, "SHORT", "breakdown", "YATAY", NOW)["qualified"])
        self.assertFalse(evaluate(state, "BUY", "trend", "YATAY", NOW)["qualified"])

    def test_one_huge_lucky_paper_win_cannot_unlock(self):
        state = upside_probe_state()
        state["signalStats"]["spot:breakout"] = {
            "closed": 1, "wins": 1, "netTry": 19,
            "meanRoi": .19}
        self.assertFalse(evaluate(
            state, "BUY", "breakout", "YATAY", NOW)["qualified"])

    def test_stale_and_correlated_forward_outcomes_block_probe(self):
        state = upside_probe_state()
        rows = state["forwardEvidence"]["completed"]
        for r in rows:
            r["at"] = rows[0]["at"]
        self.assertFalse(evaluate(
            state, "BUY", "breakout", "YATAY", NOW)["qualified"])
        state = upside_probe_state()
        for r in state["forwardEvidence"]["completed"]:
            r["measuredAt"] = (NOW - dt.timedelta(hours=5)).isoformat()
        self.assertFalse(evaluate(
            state, "BUY", "breakout", "YATAY", NOW)["qualified"])
        state = upside_probe_state()
        state["forwardEvidence"]["completed"][-1]["netReturnPct"] = -3.1
        self.assertFalse(evaluate(
            state, "BUY", "breakout", "YATAY", NOW)["qualified"])

    def test_no_more_than_two_open_breakout_positions(self):
        state = upside_probe_state()
        for index in range(2):
            symbol = f"TEST{index}USDT"
            state["holdings"][symbol] = {"quantity": 1, "costTry": 50}
            state["openSignals"][symbol] = {"setup": "breakout", "side": "buy"}
        r = evaluate(state, "BUY", "breakout", "YATAY", NOW)
        self.assertFalse(r["qualified"])
        self.assertEqual(r["openBreakoutPositions"], 2)

    def test_losing_spot_trend_and_short_are_rejected(self):
        state = upside_probe_state()
        self.assertTrue(historical_loss_guard(state, "BUY", "trend")["blocked"])
        self.assertFalse(historical_loss_guard(state, "BUY", "breakout")["blocked"])
        self.assertTrue(historical_loss_guard(state, "SHORT", "breakdown")["blocked"])
        self.assertTrue(historical_loss_guard(state, "SHORT", "trend")["blocked"])

    def test_proven_positive_future_short_evidence_can_reassess_after_losses(self):
        state = upside_probe_state()
        state["forwardEvidence"]["completed"] += [
            sample("SHORT", "breakdown", "YATAY", .5, i)
            for i in range(24)]
        # The broad entry guard still applies; this only removes one brake.
        self.assertFalse(historical_loss_guard(
            state, "SHORT", "breakdown")["blocked"])

    def test_broad_loss_circuit_does_not_block_verified_small_spot_probe(self):
        state = upside_probe_state()
        # Broad last 24 are negative, with 9/24 wins (37.5%), while the
        # last 12 have 5 winners to avoid the independent per-setup gate.
        losses = ([-.8] * 8 + [.2] * 4) + ([-.8] * 7 + [.2] * 5)
        for i, v in enumerate(losses):
            state["forwardEvidence"]["completed"].append(
                sample("BUY", "trend", "YÜKSELİŞ", v, i + 6))
        # Sideways BTC context and a climbing distinct ETH asset.
        btc = [100.0] * 168
        rising = [100 + i * .4 for i in range(168)]
        state["histories"] = {
            "BTCUSDT": {"prices": btc, "fetchedAt": NOW.isoformat()},
            "ETHUSDT": {"prices": rising, "fetchedAt": NOW.isoformat()},
        }
        mark = rising[-1]
        state["micro"] = {
            "ETHUSDT": {"fetchedAt": NOW.isoformat(),
                        "prices": [mark * (.976 + i*.0004) for i in range(60)]}
        }
        latest = {"BTCUSDT": {"priceTry": 100, "change24h": 0},
                  "ETHUSDT": {"priceTry": mark, "change24h": 3}}
        planned = assess_decision(state, latest, NOW)
        self.assertTrue(planned["edgeCircuit"]["BUY"]["blocked"])
        self.assertTrue(planned["profitFirst"]["qualified"])
        self.assertEqual(planned["action"], "BUY")
        self.assertEqual(planned["symbol"], "ETHUSDT")
        self.assertGreater(planned["amountTry"], 5)
        self.assertLess(planned["amountTry"], 40)
        self.assertEqual(state["trades"], [])  # no imaginary execution


if __name__ == "__main__":
    unittest.main()
