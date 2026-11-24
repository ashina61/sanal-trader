import unittest

from backend.forward_edge_circuit import review, snapshot
from backend.paper_bot import assess_decision, execute, fresh_state
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def observed(side, returns):
    state = fresh_state()
    state["forwardEvidence"]["completed"] = [
        {"action": side, "netReturnPct": result}
        for result in returns
    ]
    return state


class ForwardEdgeCircuitTests(unittest.TestCase):
    def test_negative_net_evidence_blocks_new_buys(self):
        state = observed("BUY", [-.7] * 18 + [.15] * 6)
        result = review(state, "BUY")
        self.assertEqual(result["status"], "NEGATIVE_NET_EVIDENCE")
        self.assertTrue(result["blocked"])
        self.assertEqual(result["samples"], 24)
        self.assertLess(result["avgNetPct"], 0)
        self.assertFalse(review(state, "SHORT")["blocked"])

    def test_negative_net_evidence_blocks_new_shorts(self):
        state = observed("SHORT", [-.7] * 18 + [.15] * 6)
        self.assertTrue(review(state, "SHORT")["blocked"])

    def test_recent_recovery_reopens_gate_without_hidden_reset(self):
        state = observed("BUY", [-2] * 24 + [.45] * 24)
        result = review(state, "BUY")
        self.assertFalse(result["blocked"])
        self.assertEqual(result["samples"], 24)
        self.assertEqual(result["winRatePct"], 100)

    def test_small_or_invalid_sample_does_not_fake_profit(self):
        state = observed("BUY", [-1] * 19)
        state["forwardEvidence"]["completed"].append({
            "action": "BUY", "netReturnPct": float("nan")})
        row = review(state, "BUY")
        self.assertFalse(row["blocked"])
        self.assertEqual(row["status"], "COLLECTING")
        self.assertTrue(snapshot(state)["researchStillActive"])

    def test_protective_exit_never_uses_new_entry_circuit(self):
        state = observed("BUY", [-.7] * 24)
        execute(state, NOW, "BTCUSDT", "buy", 50, 100, "older spot")
        quote = {"BTCUSDT": {"symbol": "BTCUSDT", "priceTry": 93,
                             "entryEligible": False}}
        planned = assess_decision(state, quote, NOW,
                                  exits_only=True, price_only=True)
        self.assertEqual(planned["action"], "SELL")
        self.assertTrue(planned["edgeCircuit"]["BUY"]["blocked"])

    def test_research_candidates_still_flow_when_live_gate_blocks(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "netReturnPct": x}
            for x in [-.7] * 18 + [.15] * 6
        ]
        live = assess_decision(state, quotes, NOW)
        research = assess_decision(state, quotes, NOW, research_only=True)
        self.assertEqual(live["action"], "WAIT")
        self.assertIn("net sonuç negatif", str(live["rejectReasons"]))
        self.assertTrue(live["edgeCircuit"]["BUY"]["blocked"])
        self.assertTrue(any(x["symbol"] == "BTCUSDT"
                            for x in research["candidates"]))
        self.assertIsNone(research["order"])
        self.assertEqual(state["trades"], [])


if __name__ == "__main__":
    unittest.main()
