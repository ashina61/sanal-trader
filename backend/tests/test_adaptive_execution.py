import datetime as dt
import unittest
from unittest.mock import patch

from backend import adaptive_execution as a


class AdaptiveExecutionTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 11, 26, 14, tzinfo=dt.timezone.utc)
        self.rows = [
            {"model": a.MODEL, "symbol": "COIN%d" % (i % 8),
             "at": (self.now-dt.timedelta(minutes=(23-i)*22)).isoformat(),
             "netPct": 2 if i % 3 else -1}
            for i in range(24)]
        self.state = {"ohlcvReaderActive": True, "cashTry": 650,
                      "holdings": {}, "shorts": {}, "openSignals": {},
                      "strategyLabV1": {"breakout_retest": {"observedExitPathsV1": self.rows}}}

    def test_lane_needs_its_own_fresh_profitable_results(self):
        self.assertTrue(a.lane_evidence(self.state, "breakout_retest", self.now)["ready"])
        self.assertFalse(a.lane_evidence(self.state, "support_reclaim", self.now)["ready"])
        self.assertFalse(a.lane_evidence(self.state, "breakout_retest",
                                        self.now+dt.timedelta(hours=4))["ready"])
        self.state["signalStats"] = {"spot:adaptive:breakout_retest": {"closed": 3, "netTry": -2}}
        self.assertFalse(a.lane_evidence(self.state, "breakout_retest", self.now)["ready"])

    def test_one_wallet_bounded_order_and_no_unqualified_short(self):
        latest = {"ABCUSDT": {"priceTry": 100}}
        with patch.object(a, "classify", return_value=[
                ("breakout_retest", "BUY", 1.5), ("breakdown_retest", "SHORT", 2)]), patch.object(a, "entry_veto", return_value=None):
            choices = a.candidates(self.state, latest, self.now, 650, 0)
            self.assertEqual(len(choices), 1)
            self.assertEqual(choices[0]["action"], "BUY")
            self.assertLessEqual(choices[0]["amountTry"], 117)
            self.assertGreater(choices[0]["targetNetTry"], 2)
            self.state["openSignals"]["OTHER"] = {"setup": a.PREFIX+"support_reclaim"}
            self.assertEqual(a.candidates(self.state, latest, self.now, 650, 0), [])
        self.assertEqual(self.state["cashTry"], 650)

    def test_observed_fee_adjusted_exit(self):
        self.state["holdings"]["ABC"] = {"quantity": 1, "costTry": 100.1}
        self.state["openSignals"]["ABC"] = {"side": "buy", "setup": a.PREFIX+"breakout_retest",
                                            "amountTry": 100, "openedAt": self.now.isoformat()}
        self.assertIn("kâr al", a.exit_reason(self.state, "ABC", "buy", 103, self.now))
        self.assertIn("zarar kes", a.exit_reason(self.state, "ABC", "buy", 98, self.now))
        self.assertIsNone(a.exit_reason(self.state, "ABC", "buy", 100, self.now))
        self.assertIn("süre", a.exit_reason(self.state, "ABC", "buy", 100,
                                          self.now+dt.timedelta(hours=1)))


    def test_small_positive_sample_is_pilot_not_validated_and_limited(self):
        rows = self.rows[-3:]
        self.state["strategyLabV1"]["breakout_retest"]["observedExitPathsV1"] = rows
        proof = a.lane_evidence(self.state, "breakout_retest", self.now)
        self.assertFalse(proof["ready"])
        self.assertTrue(proof["pilotReady"])
        with patch.object(a, "classify", return_value=[("breakout_retest", "BUY", 1.5)]), patch.object(a, "entry_veto", return_value=None):
            latest = {"ABCUSDT": {"priceTry": 100}}
            choices = a.candidates(self.state, latest, self.now, 650, 0)
            self.assertEqual(len(choices), 1)
            self.assertTrue(choices[0]["evidence"]["exploratoryPaperOnly"])
            self.assertLessEqual(choices[0]["amountTry"], 78)
            self.state["trades"] = [{"at": self.now.isoformat(), "side": "sell",
                                    "reason": "Adaptif deneme zarar kes", "realizedPnlTry": -2.1}]
            self.assertEqual(a.candidates(self.state, latest, self.now, 650, 0), [])


if __name__ == "__main__":
    unittest.main()
