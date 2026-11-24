"""Regression: all price exits are observed and use the original paper wallet."""
import unittest

from backend.profit_protection import (
    SPOT_HARD_STOP_PCT, SHORT_HARD_STOP_PCT,
    spot_giveback, short_giveback,
)
from backend.paper_bot import assess_decision, execute, fresh_state
from backend.short_positions import open_short
from backend.tests.test_paper_bot import NOW


def quote(price):
    return {"BTCUSDT": {"priceTry": price, "change24h": 0.0}}


class ProfitProtectionTests(unittest.TestCase):
    def test_no_fabricated_peak_data_and_invalid_numbers_never_exit(self):
        self.assertFalse(spot_giveback(100, 99, None))
        self.assertFalse(spot_giveback(100, 101, 100))
        self.assertFalse(short_giveback(100, 101, None))
        self.assertFalse(short_giveback(100, 99, float("nan")))

    def test_spot_profit_giveback_detected_even_after_fee_positive_trailing_gap(self):
        state = fresh_state()
        execute(state, NOW, "BTCUSDT", "buy", 65, 100, "observed buy")
        entry = state["holdings"]["BTCUSDT"]["costTry"] / state["holdings"]["BTCUSDT"]["quantity"]
        state["peakMarksTry"] = {"BTCUSDT": entry * 1.019}
        price = entry * 1.002
        self.assertTrue(spot_giveback(entry, price, entry * 1.019))
        planned = assess_decision(state, quote(price), NOW,
                                  exits_only=True, price_only=True)
        self.assertEqual(planned["action"], "SELL")
        self.assertIn("tepe kârını geri vermeme", planned["reason"])
        self.assertEqual(len(state["trades"]), 1)  # no imaginary fill
        self.assertEqual(len(state["holdings"]), 1)

    def test_short_profit_giveback_prioritizes_cover_near_entry(self):
        state = fresh_state()
        open_short(state, NOW, "BTCUSDT", 65, 100, "observed short")
        state["troughMarksTry"] = {"BTCUSDT": 98}
        self.assertTrue(short_giveback(100, 100.1, 98))
        planned = assess_decision(state, quote(100.1), NOW,
                                  exits_only=True, price_only=True)
        self.assertEqual(planned["action"], "COVER")
        self.assertIn("dip kârını geri vermeme", planned["reason"])
        self.assertIn("BTCUSDT", state["shorts"])

    def test_hard_risk_cap_reaches_before_old_4_5pct_level(self):
        state = fresh_state()
        execute(state, NOW, "BTCUSDT", "buy", 65, 100, "observed buy")
        entry = state["holdings"]["BTCUSDT"]["costTry"] / state["holdings"]["BTCUSDT"]["quantity"]
        stop = assess_decision(state, quote(entry * (1-SPOT_HARD_STOP_PCT-.001)),
                               NOW, exits_only=True, price_only=True)
        self.assertEqual(stop["action"], "SELL")
        self.assertIn("zarar kes", stop["reason"])
        self.assertEqual(len(state["trades"]), 1)

        short = fresh_state()
        open_short(short, NOW, "BTCUSDT", 65, 100, "observed short")
        cover = assess_decision(short, quote(100*(1+SHORT_HARD_STOP_PCT+.001)),
                                NOW, exits_only=True, price_only=True)
        self.assertEqual(cover["action"], "COVER")
        self.assertIn("zarar kes", cover["reason"])
        self.assertEqual(len(short["trades"]), 1)

    def test_small_moves_and_non_observed_profit_do_not_force_exit(self):
        long = fresh_state()
        execute(long, NOW, "BTCUSDT", "buy", 65, 100, "observed buy")
        entry = long["holdings"]["BTCUSDT"]["costTry"] / long["holdings"]["BTCUSDT"]["quantity"]
        long["peakMarksTry"] = {"BTCUSDT": entry * 1.007}
        planned = assess_decision(long, quote(entry * .996), NOW,
                                  exits_only=True, price_only=True)
        self.assertEqual(planned["action"], "WAIT")
        self.assertFalse(spot_giveback(entry, entry*.996, entry*1.007))


if __name__ == "__main__":
    unittest.main()
