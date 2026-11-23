"""Performance, no-lookahead evidence gating, and one-wallet safety."""
import datetime as dt
import threading
import time
import unittest

from backend.scan_engine import fetch_candle_batch
from backend.evidence_guard import entry_gate, gate_summary
from backend.paper_bot import assess_decision, fresh_state, cycle
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import FakeMarket, NOW, quote


class ParallelCandleTests(unittest.TestCase):
    def test_six_bounded_workers_overlap_but_results_are_deterministic(self):
        lock = threading.Lock()
        peak = [0]
        active = [0]
        def request(symbol):
            with lock:
                active[0] += 1
                peak[0] = max(peak[0], active[0])
            time.sleep(.012)
            with lock:
                active[0] -= 1
            if symbol == "C":
                raise TimeoutError("Public candle unavailable")
            return [1.0, 2.0, 3.0]
        values, stats = fetch_candle_batch(
            request, {"D", "A", "C", "B"},
            lambda rows: rows, minimum=3, workers=4)
        self.assertGreaterEqual(peak[0], 2)
        self.assertEqual(list(values), ["A", "B", "D"])
        self.assertEqual(stats["requested"], 4)
        self.assertEqual(stats["valid"], 3)
        self.assertEqual(stats["failed"], 1)
        self.assertLess(stats["elapsedSec"], 0.10)

    def test_bad_data_omitted_without_fabricated_price(self):
        received, stats = fetch_candle_batch(
            lambda symbol: [10, 11] if symbol == "LATE" else [],
            ["LATE", "EMPTY"], lambda x: x, minimum=3)
        self.assertEqual(received, {})
        self.assertEqual(stats["failed"], 2)
        self.assertEqual(fetch_candle_batch(
            lambda _: [], [], lambda x: x, 3)[1]["requested"], 0)
        with self.assertRaises(ValueError):
            fetch_candle_batch(lambda _: [], ["A"], lambda x: x, 3,
                               workers=100)

    def test_cycle_exposes_observed_scan_metrics_without_second_order(self):
        marks = [quote("USDTTRY", 40),
                 quote("BTCUSDT", 100)]
        result = cycle(fresh_state(), FakeMarket(marks), NOW)
        self.assertIsNone(result["lastError"])
        self.assertIn("scanStats", result["decisionPlan"])
        self.assertEqual(result["scanStats"]["workers"], 6)
        self.assertIn("evidenceGuard", result["decisionPlan"])
        self.assertEqual(result["trades"], [])


class EvidenceGuardTests(unittest.TestCase):
    def test_weak_observed_buys_pause_entries_but_research_continues(self):
        state, latest = market_prices(
            [100 + i * .4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "netReturnPct": -1}
            for _ in range(12)]
        decision = assess_decision(state, latest, NOW)
        self.assertEqual(decision["action"], "WAIT")
        self.assertIn("Son gözlenen sinyal", decision["rejectReasons"])
        shadow = assess_decision(state, latest, NOW, research_only=True)
        self.assertEqual(shadow["action"], "WAIT")
        self.assertIsNone(shadow["order"])
        self.assertTrue(any(c["action"] == "BUY" for c in shadow["candidates"]))
        self.assertEqual(state["trades"], [])

    def test_negative_short_evidence_guard_is_not_short_trade(self):
        state, latest = market_prices(
            [200 - i * .5 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            {"action": "SHORT", "netReturnPct": -2}
            for _ in range(7)]
        decision = assess_decision(state, latest, NOW)
        self.assertEqual(decision["action"], "WAIT")
        self.assertTrue(entry_gate(state, "SHORT")["blocked"])
        self.assertFalse(entry_gate(state, "BUY")["blocked"])
        shadow = assess_decision(state, latest, NOW, research_only=True)
        self.assertTrue(shadow["candidates"])

    def test_observed_recovery_unblocks_entry_without_cash_reset(self):
        state, latest = market_prices(
            [100 + i * .4 for i in range(168)])
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "netReturnPct": -1}
            for _ in range(12)]
        self.assertTrue(entry_gate(state, "BUY")["blocked"])
        state["forwardEvidence"]["completed"].extend(
            {"action": "BUY", "netReturnPct": 1}
            for _ in range(12))
        self.assertFalse(entry_gate(state, "BUY")["blocked"])
        self.assertEqual(assess_decision(state, latest, NOW)["action"], "BUY")
        self.assertEqual(state["cashTry"], 650)
        self.assertEqual(gate_summary(state)["BUY"]["samples"], 12)

    def test_sample_too_small_never_claims_certainty(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "netReturnPct": -4}
            for _ in range(11)]
        self.assertFalse(entry_gate(state, "BUY")["blocked"])
        self.assertIsNone(entry_gate(state, "SHORT")["avgNetPct"])


if __name__ == "__main__":
    unittest.main()
