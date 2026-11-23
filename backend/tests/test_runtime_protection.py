"""Exit latency, partial-feed safety, and truthful cycle diagnostics."""
import datetime as dt
import unittest

from backend.paper_bot import closes, cycle, execute, fresh_state, stamp
from backend.short_positions import open_short
from backend.tests.test_paper_bot import FakeMarket, NOW, quote


class ProtectionTests(unittest.TestCase):
    def position(self, symbol="BTCUSDT"):
        state = fresh_state()
        execute(state, NOW - dt.timedelta(hours=2), symbol,
                "buy", 50, 4000, "existing position")
        return state

    def test_all_price_stops_close_before_charts_news_or_ai(self):
        state = self.position()
        execute(state, NOW - dt.timedelta(hours=2), "ETHUSDT",
                "buy", 50, 4000, "existing position")
        open_short(state, NOW - dt.timedelta(hours=2), "SOLUSDT",
                   50, 4000, "existing short")

        class SlowOptionalServices(FakeMarket):
            calls = []

            def candles(self, symbol):
                self.calls.append('charts')
                raise AssertionError("Charts must not precede protective stops")

            def news(self, t):
                self.calls.append('news')
                raise AssertionError("News must not precede protective stops")

        market = SlowOptionalServices([
            quote("USDTTRY", 40), quote("BTCUSDT", 90),
            quote("ETHUSDT", 90), quote("SOLUSDT", 110)])
        result = cycle(state, market, NOW)
        self.assertEqual(result["holdings"], {})
        self.assertEqual(result["shorts"], {})
        self.assertEqual(len(result["trades"]), len(state["trades"]) + 3)
        self.assertEqual(result["initialCashTry"], 650)
        self.assertIsNone(result["lastError"])
        self.assertEqual(result["runtimeStatus"]["phase"], "PROTECTED")
        self.assertEqual(result["runtimeStatus"]["exitOrders"], 3)
        self.assertFalse(result["runtimeStatus"]["scanCompleted"])
        self.assertEqual(result["runtimeStatus"]["scanCoverage"], {})
        self.assertEqual(len(result["decisionPlan"]["exitBatch"]), 3)
        self.assertEqual(market.calls, [])
        # Input is immutable and closures are not repeated on the next run.
        self.assertEqual(len(state["holdings"]), 2)
        next_result = cycle(result, market, NOW + dt.timedelta(minutes=2))
        self.assertEqual(result["trades"], next_result["trades"])

    def test_missing_other_price_cannot_block_valid_stop(self):
        state = self.position()
        execute(state, NOW - dt.timedelta(hours=2), "ETHUSDT",
                "buy", 50, 4000, "other holding")
        result = cycle(state, FakeMarket([
            quote("USDTTRY", 40), quote("BTCUSDT", 90)]), NOW)
        self.assertNotIn("BTCUSDT", result["holdings"])
        self.assertIn("ETHUSDT", result["holdings"])
        self.assertEqual(result["runtimeStatus"]["exitOrders"], 1)
        self.assertEqual(result["runtimeStatus"]["phase"], "ERROR")
        self.assertEqual(result["runtimeStatus"]["missingPositionQuotes"], ["ETHUSDT"])
        self.assertIsNone(result["lastSuccessAt"])
        self.assertIn("kaydedildi", result["lastDecision"])
        self.assertEqual(result["trades"][0]["side"], "sell")

    def test_old_ticker_does_not_fill_a_stop_at_stale_price(self):
        state = self.position()
        old = NOW - dt.timedelta(minutes=2)
        result = cycle(state, FakeMarket([
            quote("USDTTRY", 40, old), quote("BTCUSDT", 90, old)]), NOW)
        self.assertEqual(result["trades"], state["trades"])
        self.assertEqual(result["runtimeStatus"]["phase"], "ERROR")
        self.assertIsNone(result["runtimeStatus"]["exitCheckedAt"])

    def test_new_entry_liquidity_screen_cannot_block_existing_stop(self):
        state = self.position()
        result = cycle(state, FakeMarket([
            quote("USDTTRY", 40), quote("BTCUSDT", 90, volume=500)]), NOW)
        self.assertEqual(result["holdings"], {})
        self.assertEqual(result["runtimeStatus"]["phase"], "PROTECTED")

    def test_technical_exit_skips_news_fetch(self):
        state = self.position()
        state["histories"]["BTCUSDT"] = {
            "fetchedAt": stamp(NOW), "prices": [5000 - 6 * i for i in range(168)]}

        class NewsMarket(FakeMarket):
            news_calls = 0

            def news(self, t):
                self.news_calls += 1
                return {}

        market = NewsMarket([quote("USDTTRY", 40), quote("BTCUSDT", 97)])
        result = cycle(state, market, NOW)
        self.assertIsNone(result["lastError"])
        self.assertEqual(result["holdings"], {})
        self.assertEqual(result["trades"][0]["side"], "sell")
        self.assertEqual(market.news_calls, 0)


class RuntimeTests(unittest.TestCase):
    def test_old_closed_bars_are_not_fresh_confirmation(self):
        old = int((NOW - dt.timedelta(minutes=10)).timestamp() * 1000)
        bars = [[old - 60000, '10', '10', '10', '10', '1', old]]
        self.assertEqual(closes(bars, NOW, 40, max_age=180), [])
        self.assertEqual(closes(bars, NOW, 40, max_age=1800), [400.0])

    def test_wait_with_failed_charts_is_partial_data_not_healthy(self):
        result = cycle(fresh_state(), FakeMarket([
            quote("USDTTRY", 40), quote("BTCUSDT", 100)]), NOW)
        status = result["runtimeStatus"]
        self.assertEqual(status["phase"], "DEGRADED")
        self.assertTrue(status["scanCompleted"])
        self.assertEqual(status["scanCoverage"]["hourly"]["failed"], 1)
        self.assertEqual(status["marketObservedAt"], stamp(NOW))
        self.assertEqual(status["oldestQuoteAt"], stamp(NOW))
        self.assertEqual(status["quotesReceived"], 2)
        self.assertEqual(result["trades"], [])

    def test_duplicate_heartbeat_never_claims_new_scan(self):
        state = fresh_state()
        state["lastSuccessAt"] = stamp(NOW)
        result = cycle(state, FakeMarket([]), NOW + dt.timedelta(seconds=30))
        status = result["runtimeStatus"]
        self.assertEqual(status["phase"], "SKIPPED")
        self.assertFalse(status["scanCompleted"])
        self.assertIsNone(status["marketObservedAt"])
        self.assertEqual(result["lastSuccessAt"], stamp(NOW))

    def test_disabled_wallet_has_no_market_or_exit_claim(self):
        state = fresh_state()
        state["enabled"] = False
        result = cycle(state, FakeMarket([]), NOW)
        self.assertEqual(result["runtimeStatus"]["phase"], "PAUSED")
        self.assertIsNone(result["runtimeStatus"]["exitCheckedAt"])
        self.assertEqual(result["cashTry"], 650)

    def test_live_clock_revalues_after_scan_with_new_observation_time(self):
        later = NOW + dt.timedelta(seconds=50)

        class UpdatedMarket(FakeMarket):
            calls = 0

            def tickers(self):
                self.calls += 1
                at = NOW if self.calls == 1 else later
                return [quote("USDTTRY", 40, at), quote("BTCUSDT", 100, at)]

        times = iter([NOW, later])
        result = cycle(fresh_state(), UpdatedMarket([]), NOW,
                       clock=lambda: next(times))
        self.assertIsNone(result["lastError"])
        self.assertEqual(result["lastSuccessAt"], stamp(later))
        self.assertEqual(result["runtimeStatus"]["marketObservedAt"], stamp(later))
        self.assertEqual(result["runtimeStatus"]["oldestQuoteAt"], stamp(later))


if __name__ == "__main__":
    unittest.main()
