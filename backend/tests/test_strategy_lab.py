import copy
import datetime as dt
import unittest
from unittest.mock import patch

from backend import strategy_lab as lab


class StrategyLabTests(unittest.TestCase):
    def setUp(self):
        self.now = dt.datetime(2026, 11, 26, 5, 0, tzinfo=dt.timezone.utc)
        self.chart = {
            "1h": {"trend": "UP"},
            "15m": {"trend": "UP", "supportTry": 98, "resistanceTry": 103},
            "1m": {"trend": "UP", "rsi": 55, "volumeRatio": 1.5,
                   "atrPct": .2, "pattern": "BULL_BODY",
                   "bullTrap": False, "bearTrap": False}}
        self.state = {"ohlcvReaderActive": True, "cashTry": 650,
                      "holdings": {}, "shorts": {}, "trades": [],
                      "micro": {"ABCUSDT": {"prices":
                          [99.8]*5 + [100]*20 + [100.4, 100.1, 100, 100.1, 100.3]}}}

    def test_breakout_retest_and_no_chasing(self):
        with patch.object(lab, "reports", return_value=self.chart):
            self.assertIn(("breakout_retest", "BUY", 1.5),
                          lab.classify(self.state, "ABCUSDT", 100.3, self.now))
            self.assertEqual(lab.classify(self.state, "ABCUSDT", 101, self.now), [])
            self.chart["1m"]["rsi"] = 78
            self.assertEqual(lab.classify(self.state, "ABCUSDT", 100.3, self.now), [])

    def test_short_exhaustion_and_position_cluster(self):
        with patch.object(lab, "reports", return_value=self.chart):
            self.chart["1m"]["rsi"] = 30
            self.assertIsNotNone(lab.entry_veto(self.state, "ABCUSDT", "short", self.now))
            self.chart["1m"]["rsi"] = 45
            self.state["shorts"]["XYZUSDT"] = {}
            self.assertIsNotNone(lab.entry_veto(self.state, "ABCUSDT", "short", self.now))
            self.state["shorts"].clear()
            self.assertIsNone(lab.entry_veto(self.state, "ABCUSDT", "short", self.now))

    def test_missing_chart_blocks_live_not_exit(self):
        with patch.object(lab, "reports", return_value={}):
            self.assertIsNotNone(lab.entry_veto(self.state, "ABCUSDT", "buy", self.now))
            self.assertEqual(lab.classify(self.state, "ABCUSDT", 100, self.now), [])

    def test_observation_uses_later_price_never_wallet(self):
        wallet = copy.deepcopy(self.state)
        with patch.object(lab, "classify", return_value=[("breakout_retest", "BUY", 1.5)]):
            report = lab.observe(self.state, {"ABCUSDT": {"priceTry": 100}}, self.now)
        self.assertEqual(report["lanes"]["breakout_retest"]["samples"], 0)
        self.assertEqual(report["lanes"]["breakout_retest"]["pending"], 1)
        with patch.object(lab, "classify", return_value=[]):
            report = lab.observe(self.state, {"ABCUSDT": {"priceTry": 101}},
                                 self.now + dt.timedelta(hours=1))
        self.assertEqual(report["lanes"]["breakout_retest"]["samples"], 1)
        self.assertAlmostEqual(report["lanes"]["breakout_retest"]["avgNetPct"], .7)
        self.assertFalse(report["automaticOrder"])
        self.assertEqual({k:v for k,v in self.state.items() if k != "strategyLabV1"}, wallet)

    def test_same_direction_correlation_guard(self):
        self.state["holdings"]["XYZUSDT"] = {}
        with patch.object(lab, "reports", return_value=self.chart), patch.object(lab, "correlation", return_value=.95):
            self.assertIsNotNone(lab.entry_veto(self.state, "ABCUSDT", "buy", self.now))


    def test_observed_exit_path_keeps_first_target_without_future_fill(self):
        with patch.object(lab, "classify", return_value=[("breakout_retest", "BUY", 1.5)]):
            lab.observe(self.state, {"ABCUSDT": {"priceTry": 100}}, self.now)
        with patch.object(lab, "classify", return_value=[]):
            report = lab.observe(self.state, {"ABCUSDT": {"priceTry": 101.5}},
                                 self.now + dt.timedelta(minutes=10))
            models = report["lanes"]["breakout_retest"]["exitPathModels"]
            self.assertEqual(models["net1_stop1"]["targetHits"], 1)
            self.assertAlmostEqual(models["net1_stop1"]["avgNetPct"], 1.2)
            self.assertEqual(models["net2_stop1"]["samples"], 0)
            report = lab.observe(self.state, {"ABCUSDT": {"priceTry": 98}},
                                 self.now + dt.timedelta(hours=1))
        models = report["lanes"]["breakout_retest"]["exitPathModels"]
        self.assertEqual(models["net1_stop1"]["targetHits"], 1)
        self.assertEqual(models["net1_stop1"]["samples"], 1)
        self.assertEqual(models["net2_stop1"]["stopHits"], 1)
        self.assertAlmostEqual(models["net2_stop1"]["avgNetPct"], -2.3)
        self.assertAlmostEqual(report["lanes"]["breakout_retest"]["avgNetPct"], -2.3)
        self.assertEqual(self.state["cashTry"], 650)
        self.assertEqual(self.state["trades"], [])


if __name__ == "__main__":
    unittest.main()
