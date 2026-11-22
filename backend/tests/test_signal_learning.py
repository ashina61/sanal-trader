import unittest
from backend.signal_learning import (
    minute_signal, setup_for, signal_bias, record_open, record_close,
)


class SignalLearningTests(unittest.TestCase):
    def test_minute_signal_uses_real_closed_samples_and_observed_mark(self):
        bars = [100 + i * .02 for i in range(60)]
        signal = minute_signal(bars, bars[-1])
        self.assertIsNotNone(signal)
        self.assertGreater(signal["momentum5"], 0)
        self.assertTrue(signal["breakout"])
        self.assertEqual(setup_for(signal, "buy"), "breakout")
        self.assertEqual(signal["upBars5"], 4)
        self.assertIsNone(minute_signal(bars[:10], bars[9]))
        self.assertIsNone(minute_signal(bars, bars[-1] * 1.20))

    def test_online_bias_only_after_real_closed_outcomes(self):
        state = {}
        for i in range(4):
            key = f"COIN{i}USDT"
            record_open(state, key, "buy", "breakout", 40.0, "2026-11-23T00:00:00Z")
            record_close(state, key, 2.0)
        self.assertEqual(signal_bias(state, "buy", "breakout"), 0)
        record_open(state, "COIN5USDT", "buy", "breakout", 40.0, "2026-11-23T00:00:00Z")
        record_close(state, "COIN5USDT", 2.0)
        self.assertGreater(signal_bias(state, "buy", "breakout"), 0)
        self.assertEqual(signal_bias(state, "short", "breakout"), 0)
        self.assertEqual(state["signalStats"]["spot:breakout"]["closed"], 5)
        record_close(state, "COIN5USDT", 2.0)
        self.assertEqual(state["signalStats"]["spot:breakout"]["closed"], 5)

    def test_losses_reduce_score_but_cannot_override_safety(self):
        state = {}
        for i in range(12):
            k = f"LOSS{i}"
            record_open(state, k, "short", "breakdown", 40.0, "now")
            record_close(state, k, -2.0)
        self.assertLess(signal_bias(state, "short", "breakdown"), 0)
        self.assertGreaterEqual(signal_bias(state, "short", "breakdown"), -.20)


if __name__ == "__main__":
    unittest.main()
