"""Regression tests for complete candidate chart coverage and entry ranking."""
import datetime as dt
import unittest

from backend.paper_bot import cycle, entry_quality_score, fresh_state
from backend.tests.test_paper_bot import FakeMarket, NOW, quote


class EntryQualityTests(unittest.TestCase):
    def setUp(self):
        self.hourly = {"score": .90, "volatility": 4.0, "momentum6": 1.8}
        self.strong_fast = {"momentum1h": .70, "momentum4h": 1.7}
        self.weak_fast = {"momentum1h": .16, "momentum4h": .63}
        self.strong_micro = {"momentum5": .46, "momentum15": .95,
                             "breakout": True, "breakdown": False}
        self.weak_micro = {"momentum5": .13, "momentum15": .31,
                           "breakout": False, "breakdown": False}

    def test_stronger_confirmed_follow_through_beats_equal_hourly_score(self):
        strong = entry_quality_score(
            self.hourly, self.strong_fast, self.strong_micro, "buy")
        weak = entry_quality_score(
            self.hourly, self.weak_fast, self.weak_micro, "buy")
        self.assertGreater(strong, weak)

    def test_higher_volatility_lowers_quality_and_learning_remains_bounded(self):
        stable = entry_quality_score(self.hourly, None, None, "buy")
        noisy = entry_quality_score(
            dict(self.hourly, volatility=7.4), None, None, "buy")
        self.assertGreater(stable, noisy)
        self.assertGreater(entry_quality_score(
            self.hourly, None, None, "buy", .07), stable)

    def test_short_scores_are_symmetric_for_confirmed_downtrend(self):
        bearish = dict(self.hourly, score=-.90, momentum6=-1.8)
        down_fast = {"momentum1h": -.70, "momentum4h": -1.7}
        down_micro = {"momentum5": -.46, "momentum15": -.95,
                      "breakout": False, "breakdown": True}
        self.assertAlmostEqual(
            entry_quality_score(
                bearish, down_fast, down_micro, "short"),
            entry_quality_score(
                self.hourly, self.strong_fast, self.strong_micro, "buy"))

    def test_all_shortlisted_symbols_receive_both_timeframes(self):
        class FullMarket(FakeMarket):
            def bars(self, period, n):
                out = []
                for i in range(n):
                    at = NOW - dt.timedelta(minutes=period * (n - i))
                    ms = int(at.timestamp() * 1000)
                    out.append([ms - period * 60000, "10", "10", "10",
                                "10", "1", ms, "100"])
                return out

            def candles_fast(self, symbol):
                return self.bars(15, 96)

            def candles_minute(self, symbol):
                return self.bars(1, 65)

        ticks = [quote("USDTTRY", 40)]
        for i in range(45):
            item = quote(f"COIN{i:02d}USDT", 10,
                         volume=60_000_000 - i * 1_000_000)
            if i == 44:
                item["openPrice"] = "20"
            ticks.append(item)
        result = cycle(fresh_state(), FullMarket(ticks), NOW)
        self.assertIsNone(result["lastError"])
        self.assertGreater(result["screened"], 36)
        self.assertEqual(result["minutePairs"], result["screened"])
        self.assertEqual(result["intradayPairs"], result["screened"])
        self.assertEqual(result["trades"], [])


if __name__ == "__main__":
    unittest.main()
