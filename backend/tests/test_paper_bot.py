import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path

from backend.paper_bot import (
    FEE, MIN_ORDER, as_date, assess_decision, closes, cycle, eligible, equity, execute,
    fresh_state, indicators, load, pick, quotes, record_trigger,
    record_performance, update_price_extremes, save, stamp,
)

UTC = dt.timezone.utc
NOW = dt.datetime(2026, 11, 22, 12, 0, tzinfo=UTC)

def quote(symbol, price, t=NOW, volume=40000000):
    return {
        "symbol": symbol, "lastPrice": str(price),
        "openPrice": str(price / 1.03), "quoteVolume": str(volume),
        "closeTime": int(t.timestamp() * 1000),
    }

def candles_for(price=100, t=NOW, falling=False):
    out = []
    for i in range(168):
        value = price * (1.5-i/336 if falling else .65+i/480)
        timestamp = int((t - dt.timedelta(hours=168-i)).timestamp() * 1000)
        out.append([timestamp-3600000, str(value), str(value*1.01),
            str(value*.99), str(value), "100", timestamp, "1500000"])
    return out

class FakeMarket:
    def __init__(self, ticks, candles=None):
        self.ticks = ticks
        self.history = candles or {}
    def tickers(self):
        return self.ticks
    def candles(self, symbol):
        return self.history.get(symbol, [])
    def depth(self, symbol):
        # Explicit, realistic public-book fixture. Tests must not bypass
        # the new-entry gate merely because an API is absent.
        tick = next((r for r in self.ticks if r.get("symbol") == symbol), None)
        if tick is None:
            raise ValueError("No simulated book for missing ticker")
        mid = float(tick["lastPrice"])
        return {
            "bids": [[str(mid * 0.9995), "100000"]],
            "asks": [[str(mid * 1.0005), "100000"]],
        }

class PaperBotTests(unittest.TestCase):
    def test_eligible_only_plain_spot_usdt(self):
        self.assertTrue(eligible("BTCUSDT"))
        self.assertTrue(eligible("ADAUSDT"))
        self.assertFalse(eligible("USDCUSDT"))
        self.assertFalse(eligible("BTCUPUSDT"))
        self.assertFalse(eligible("BTCTRY"))
        # Binance bStocks are listed on the spot ticker, but must not enter
        # a cryptocurrency-only strategy. Never block an existing exit.
        for symbol in ("CRCLBUSDT", "INTCBUSDT", "METABUSDT",
                       "SPCXBUSDT", "NVDABUSDT", "AAPLBUSDT"):
            self.assertFalse(eligible(symbol))
        self.assertTrue(eligible("BNBUSDT"))
        self.assertTrue(eligible("TRXUSDT"))

    def test_legacy_stock_token_position_still_gets_protective_sell(self):
        state = fresh_state()
        execute(state, NOW, "CRCLBUSDT", "buy", 50, 100, "legacy position")
        live = {"CRCLBUSDT": {"symbol": "CRCLBUSDT", "priceTry": 93,
                               "entryEligible": False}}
        decision = assess_decision(state, live, NOW,
                                   exits_only=True, price_only=True)
        self.assertEqual(decision["action"], "SELL")
        self.assertEqual(decision["symbol"], "CRCLBUSDT")

    def test_missing_fx_stops_paper_trading(self):
        with self.assertRaises(ValueError):
            quotes([quote("BTCUSDT", 100)], NOW)
        stale = quote("USDTTRY", 40, NOW-dt.timedelta(minutes=20))
        with self.assertRaises(ValueError):
            quotes([quote("BTCUSDT", 100), stale], NOW)

    def test_unclosed_hour_never_enters_analysis(self):
        bars = candles_for()
        self.assertEqual(len(closes(bars, NOW, 40)), 168)
        future = [1, "1", "1", "1", "999999", "5",
                  int((NOW+dt.timedelta(minutes=5)).timestamp()*1000)]
        self.assertEqual(len(closes(bars+[future], NOW, 40)), 168)

    def test_technical_requires_real_history(self):
        self.assertIsNone(indicators([100,101]))
        result = indicators(closes(candles_for(), NOW, 1))
        self.assertIsNotNone(result)
        self.assertTrue(-1 <= result["score"] <= 1)

    def test_buy_and_sell_deduct_actual_virtual_fees(self):
        state = fresh_state()
        execute(state, NOW, "BTCUSDT", "buy", 65, 100, "test")
        self.assertAlmostEqual(state["cashTry"], 650 - 65*(1+FEE))
        self.assertAlmostEqual(state["holdings"]["BTCUSDT"]["costTry"], 65.065)
        execute(state, NOW, "BTCUSDT", "sell", 71.5, 110, "test")
        self.assertEqual(state["holdings"], {})
        expected = 71.5*(1-FEE) - 65*(1+FEE)
        self.assertAlmostEqual(state["realizedTry"], expected)
        self.assertAlmostEqual(state["cashTry"], 650+expected)
        self.assertEqual(len(state["trades"]), 2)

    def test_no_trade_from_missing_exchange_rate(self):
        s = fresh_state()
        result = cycle(s, FakeMarket([quote("BTCUSDT", 100)]), NOW)
        self.assertIsNotNone(result["lastError"])
        self.assertEqual(result["cashTry"], 650)
        self.assertEqual(result["trades"], [])
        self.assertIsNone(result["lastSuccessAt"])

    def test_held_asset_missing_price_causes_halt(self):
        state = fresh_state()
        execute(state, NOW, "BTCUSDT", "buy", 50, 100, "test")
        self.assertIsNone(equity(state, {}))
        ticks = [quote("USDTTRY", 40), quote("ETHUSDT", 99)]
        result = cycle(state, FakeMarket(ticks), NOW)
        self.assertIsNotNone(result["lastError"])
        self.assertEqual(result["trades"], state["trades"])

    def test_protective_sell_is_not_blocked_by_drawdown(self):
        state = fresh_state()
        execute(state, NOW-dt.timedelta(hours=2),
                "BTCUSDT", "buy", 50, 100, "test")
        state["peakEquityTry"] = 800
        latest = {"BTCUSDT":{"priceTry":89,"change24h":-10}}
        order = pick(state, latest, NOW)
        self.assertIsNotNone(order)
        self.assertEqual(order[1], "sell")

    def test_scheduled_cycle_survives_without_browser(self):
        ticks = [quote("USDTTRY", 40)]
        histories = {}
        for pair in ("BTCUSDT", "ETHUSDT", "ADAUSDT", "SOLUSDT"):
            ticks.append(quote(pair, 100))
            histories[pair] = candles_for()
        s = cycle(fresh_state(), FakeMarket(ticks, histories), NOW)
        self.assertIsNone(s["lastError"])
        self.assertEqual(s["tracked"], 4)
        self.assertEqual(s["lastSuccessAt"], stamp(NOW))
        self.assertEqual(s["cycles"], 1)
        self.assertGreater(s["equityTry"], 0)
        # Results are real paper price observations; a buy is optional.
        self.assertTrue(0 <= len(s["trades"]) <= 1)

    def test_repeated_short_interval_does_not_duplicate_orders(self):
        ticks = [quote("USDTTRY", 40), quote("BTCUSDT", 100)]
        market = FakeMarket(ticks, {"BTCUSDT": candles_for()})
        first = cycle(fresh_state(), market, NOW)
        next_state = cycle(first, market, NOW+dt.timedelta(seconds=60))
        self.assertEqual(len(first["trades"]), len(next_state["trades"]))

    def test_wallet_is_persistent_and_fail_closed_if_corrupt(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root)/"state.json"
            s = fresh_state()
            execute(s, NOW, "SOLUSDT", "buy", 20, 2, "test")
            save(path, s)
            reopened = load(path)
            self.assertEqual(reopened["cashTry"], s["cashTry"])
            self.assertIn("SOLUSDT", reopened["holdings"])
            path.write_text('{"schema":5,"cashTry":650}', encoding="utf-8")
            with self.assertRaises(ValueError):
                load(path)

    def test_only_actual_cron_counts_as_scheduled(self):
        state = fresh_state()
        record_trigger(state, NOW, "push")
        self.assertEqual(state["lastTriggerEvent"], "push")
        self.assertIsNone(state["lastScheduledTriggerAt"])
        scheduled = NOW + dt.timedelta(minutes=5)
        record_trigger(state, scheduled, "schedule")
        self.assertEqual(state["lastScheduledTriggerAt"], stamp(scheduled))
        record_trigger(state, scheduled + dt.timedelta(minutes=5), "workflow_dispatch")
        self.assertEqual(state["lastScheduledTriggerAt"], stamp(scheduled))
        self.assertEqual(state["cashTry"], 650.0)
        self.assertEqual(state["trades"], [])

    def test_old_wallet_remains_compatible_with_trigger_diagnostics(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "state.json"
            state = fresh_state()
            for key in ("lastTriggerEvent", "lastTriggerAt",
                        "lastScheduledTriggerAt"):
                state.pop(key)
            save(path, state)
            restored = load(path)
            self.assertIsNone(restored["lastScheduledTriggerAt"])
            self.assertEqual(restored["cashTry"], 650.0)

    def test_growth_stats_use_actual_observations_and_closed_results(self):
        state = fresh_state()
        state["equityTry"] = 654
        record_performance(state, NOW)
        self.assertEqual(state["performance"]["netTry"], 4)
        self.assertIsNone(state["performance"]["winRatePct"])
        self.assertEqual(len(state["equityHistory"]), 1)
        record_performance(state, NOW + dt.timedelta(seconds=60))
        self.assertEqual(len(state["equityHistory"]), 1)
        state["equityTry"] = 648
        record_performance(state, NOW + dt.timedelta(minutes=5))
        self.assertEqual(len(state["equityHistory"]), 2)
        self.assertGreater(state["performance"]["drawdownPct"], 0)

    def test_profit_peak_is_an_observed_price_not_invented(self):
        state = fresh_state()
        execute(state, NOW, "BTCUSDT", "buy", 65, 100, "test")
        update_price_extremes(state, {"BTCUSDT": {"priceTry": 103}})
        update_price_extremes(state, {"BTCUSDT": {"priceTry": 102}})
        self.assertEqual(state["peakMarksTry"]["BTCUSDT"], 103)
        execute(state, NOW, "BTCUSDT", "sell", 65 / 100 * 102, 102, "test")
        update_price_extremes(state, {})
        self.assertEqual(state["peakMarksTry"], {})

    def test_pause_and_resume_modes_persist_state(self):
        state = fresh_state()
        state["enabled"] = False
        result = cycle(state, FakeMarket([]), NOW)
        self.assertEqual(result["trades"], [])
        self.assertIsNone(result["lastSuccessAt"])
        self.assertFalse(result["enabled"])

if __name__ == "__main__":
    unittest.main()
