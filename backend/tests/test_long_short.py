import datetime as dt
import tempfile
import unittest
from pathlib import Path

from backend.paper_bot import (
    cycle, equity, execute, fresh_state, load, pick, save,
)
from backend.short_positions import (
    LEVERAGE, close_short, exposure, open_short, short_value,
)
from backend.tests.test_paper_bot import (
    NOW, FakeMarket, candles_for, quote,
)


class VirtualLongShortTests(unittest.TestCase):
    def test_short_falls_in_price_and_realizes_net_profit_after_fees(self):
        state = fresh_state()
        opened = open_short(state, NOW, "BTCUSDT", 65, 100, "bear signal")
        self.assertEqual(opened["side"], "short")
        self.assertEqual(opened["leverage"], 1.0)
        self.assertAlmostEqual(state["cashTry"], 584.935)
        self.assertAlmostEqual(equity(state, {"BTCUSDT":{"priceTry":100}}), 649.935)
        self.assertAlmostEqual(equity(state, {"BTCUSDT":{"priceTry":90}}), 656.435)
        closed = close_short(state, NOW, "BTCUSDT", 90, "cover")
        expected = 65 * .1 - .065 - 58.5 * .001
        self.assertAlmostEqual(closed["realizedPnlTry"], expected)
        self.assertAlmostEqual(state["cashTry"], 650 + expected)
        self.assertAlmostEqual(state["realizedTry"], expected)
        self.assertEqual(state["shorts"], {})

    def test_short_rises_in_price_and_realizes_loss(self):
        state = fresh_state()
        open_short(state, NOW, "BTCUSDT", 50, 100, "bear")
        closed = close_short(state, NOW, "BTCUSDT", 107, "stop")
        self.assertLess(closed["realizedPnlTry"], 0)
        self.assertAlmostEqual(state["cashTry"], 650 + closed["realizedPnlTry"])
        self.assertEqual(len(state["trades"]), 2)

    def test_extreme_gap_cannot_induce_negative_cash_or_debt(self):
        state = fresh_state()
        open_short(state, NOW, "BTCUSDT", 50, 100, "bear")
        self.assertEqual(short_value(state["shorts"]["BTCUSDT"], 600), 0)
        close = close_short(state, NOW, "BTCUSDT", 600, "margin safety")
        self.assertAlmostEqual(close["realizedPnlTry"], -50.05)
        self.assertGreaterEqual(state["cashTry"], 0)
        self.assertGreaterEqual(equity(state, {}), 0)

    def test_protective_short_cover_ignores_daily_entry_limit_and_drawdown(self):
        state = fresh_state()
        open_short(state, NOW, "BTCUSDT", 50, 100, "bear")
        state["todayOrders"] = 8
        state["peakEquityTry"] = 800
        latest = {"BTCUSDT":{"priceTry":107,"change24h":7}}
        decision = pick(state, latest, NOW)
        self.assertIsNotNone(decision)
        self.assertEqual(decision[1], "cover")

    def test_bearish_technical_trend_can_open_short_not_long(self):
        state = fresh_state()
        prices = [100 - i*.3 for i in range(168)]
        state["histories"]["BTCUSDT"] = {"prices": prices}
        decision = pick(state, {
            "BTCUSDT": {"priceTry": prices[-1], "change24h": -15},
        }, NOW)
        self.assertIsNotNone(decision)
        self.assertEqual(decision[1], "short")
        self.assertGreaterEqual(decision[2], 5)

    def test_no_hedging_same_symbol_and_gross_exposure_counts_short(self):
        state = fresh_state()
        open_short(state, NOW, "BTCUSDT", 60, 100, "bear")
        with self.assertRaises(ValueError):
            execute(state, NOW, "BTCUSDT", "buy", 20, 100, "opposite")
        with self.assertRaises(ValueError):
            open_short(state, NOW, "BTCUSDT", 20, 100, "duplicate")
        self.assertAlmostEqual(
            exposure(state, {"BTCUSDT":{"priceTry":100}}), 60)

    def test_legacy_wallet_short_field_migrates_without_reset(self):
        state = fresh_state()
        execute(state, NOW, "ETHUSDT", "buy", 25, 50, "old long")
        state.pop("shorts")
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/"state.json"
            save(path, state)
            restored = load(path)
            self.assertEqual(restored["shorts"], {})
            self.assertIn("ETHUSDT", restored["holdings"])
            self.assertAlmostEqual(restored["cashTry"], state["cashTry"])

    def test_short_order_survives_roundtrip_and_is_valued(self):
        state = fresh_state()
        open_short(state, NOW, "ADAUSDT", 40, 10, "bear")
        with tempfile.TemporaryDirectory() as root:
            path=Path(root)/"state.json"
            save(path,state)
            recovered=load(path)
            self.assertIn("ADAUSDT", recovered["shorts"])
            self.assertAlmostEqual(
                equity(recovered, {"ADAUSDT":{"priceTry":8}}), 657.96)

    def test_end_to_end_downtrend_can_trigger_server_paper_short(self):
        market = FakeMarket(
            [quote("USDTTRY",40),quote("BTCUSDT",100)],
            {"BTCUSDT": candles_for(price=100, falling=True)},
        )
        result = cycle(fresh_state(), market, NOW)
        self.assertIsNone(result["lastError"])
        self.assertEqual(len(result["trades"]), 1)
        self.assertEqual(result["trades"][0]["side"], "short")
        self.assertIn("BTCUSDT", result["shorts"])
        self.assertEqual(result["holdings"], {})
        self.assertAlmostEqual(result["equityTry"],
                               650-result["trades"][0]["feeTry"])


if __name__ == "__main__":
    unittest.main()
