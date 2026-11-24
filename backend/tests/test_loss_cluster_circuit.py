"""Regression: real, separated stop losses halt only NEW paper risk."""
import datetime as dt
import unittest

from backend.loss_cluster_circuit import evaluate
from backend.paper_bot import assess_decision, execute, fresh_state
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def stop(symbol, minutes_ago, net):
    return {
        "at": (NOW - dt.timedelta(minutes=minutes_ago)).isoformat(),
        "symbol": symbol, "side": "sell", "realizedPnlTry": net,
        "reason": "Spot zarar kes: düşüş %2.8",
    }


def losing_session():
    state = fresh_state()
    state["trades"] = [
        stop("NEARUSDT", 4, -.7428),
        stop("SPCXBUSDT", 12, -2.2946),
    ]
    return state


class StopClusterCircuitTests(unittest.TestCase):
    def test_recent_two_different_stop_losses_pause_only_new_risk(self):
        state = losing_session()
        initial_cash = state["cashTry"]
        initial_trades = list(state["trades"])
        circuit = evaluate(state, NOW)
        self.assertTrue(circuit["blocked"])
        self.assertEqual(circuit["status"], "RECENT_STOP_CLUSTER")
        self.assertEqual(circuit["stopsInCluster"], 2)
        self.assertGreater(circuit["remainingMinutes"], 110)
        self.assertEqual(circuit["symbols"], ["SPCXBUSDT", "NEARUSDT"])
        self.assertLess(circuit["clusterNetTry"], -3)
        self.assertTrue(circuit["protectiveExitsUnaffected"])
        self.assertEqual(state["cashTry"], initial_cash)
        self.assertEqual(state["trades"], initial_trades)

    def test_live_entry_block_but_research_still_collects_candidates(self):
        state, latest = market_prices([100 + i * .4 for i in range(168)])
        state["trades"] = losing_session()["trades"]
        live = assess_decision(state, latest, NOW)
        research = assess_decision(state, latest, NOW, research_only=True)
        self.assertTrue(live["lossCooldown"]["blocked"])
        self.assertEqual(live["action"], "WAIT")
        self.assertIn("iki zarar kes", live["reason"])
        self.assertEqual(research["action"], "WAIT")
        self.assertTrue(any(row["symbol"] == "BTCUSDT"
                            for row in research["candidates"]))
        self.assertIsNone(research["order"])
        self.assertEqual(len(state["trades"]), 2)

    def test_stop_loss_protective_sale_overrides_new_entry_cooldown(self):
        state = losing_session()
        execute(state, NOW - dt.timedelta(hours=2), "BTCUSDT",
                "buy", 50, 100, "previous paper buy")
        live = {"BTCUSDT": {"priceTry": 94,
                             "entryEligible": False}}
        plan = assess_decision(state, live, NOW,
                               exits_only=True, price_only=True)
        self.assertEqual(plan["action"], "SELL")
        self.assertEqual(plan["symbol"], "BTCUSDT")
        self.assertTrue(plan["lossCooldown"]["blocked"])
        self.assertIn("BTCUSDT", state["holdings"])

    def test_elapsed_two_hours_reopens_only_this_brake(self):
        state = losing_session()
        after = NOW + dt.timedelta(hours=2, minutes=1)
        result = evaluate(state, after)
        self.assertFalse(result["blocked"])
        self.assertEqual(result["remainingMinutes"], 0)

    def test_not_two_independent_stops_or_not_enough_total_loss(self):
        state = losing_session()
        state["trades"][0]["symbol"] = "SPCXBUSDT"
        self.assertFalse(evaluate(state, NOW)["blocked"])
        state = losing_session()
        state["trades"][0]["realizedPnlTry"] = -.05
        state["trades"][1]["realizedPnlTry"] = -.3
        self.assertFalse(evaluate(state, NOW)["blocked"])
        state = losing_session()
        state["trades"][1]["at"] = (
            NOW - dt.timedelta(minutes=100)).isoformat()
        self.assertFalse(evaluate(state, NOW)["blocked"])

    def test_broken_or_future_trades_do_not_invent_loss_cluster(self):
        state = fresh_state()
        state["trades"] = [
            stop("NEARUSDT", -5, -4), stop("SPCXBUSDT", 1, -.5),
            {"side": "sell", "at": "no-date", "realizedPnlTry": -10,
             "symbol": "TESTUSDT", "reason": "Spot zarar kes"},
        ]
        self.assertFalse(evaluate(state, NOW)["blocked"])
        self.assertEqual(evaluate(state, NOW.replace(tzinfo=None))["status"],
                         "UNKNOWN")


if __name__ == "__main__":
    unittest.main()
