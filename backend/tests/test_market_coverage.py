import datetime as dt
import io
import unittest
import urllib.error
from unittest.mock import patch

from backend.market_coverage import minute_focus, due_batch, snapshot
from backend.scan_engine import fetch_candle_batch
from backend.paper_bot import (Market, cycle, execute, fresh_state,
                               stamp, store_market_health)
from backend.tests.test_paper_bot import NOW, quote, candles_for


class CoverageTests(unittest.TestCase):
    def test_priority_is_preserved_when_requests_start_not_only_when_selected(self):
        called = []
        def request(symbol):
            called.append(symbol)
            return [1, 2, 3]
        fetch_candle_batch(request, ['A', 'B', 'Z'], lambda x: x, 3,
                           workers=1, priority=['Z'])
        self.assertEqual(called, ['Z', 'A', 'B'])

    def test_rotation_covers_beyond_top_leaders_and_always_keeps_holdings(self):
        rows = [{'symbol': f'ALT{i:03}USDT', 'volume': 40_000_000 - i,
                 'change': i / 10} for i in range(220)]
        names = {r['symbol'] for r in rows}
        cursor = 0
        seen = set()
        for _ in range(8):
            focus, policy = minute_focus(rows, names, {'ALT180USDT'}, (), cursor)
            self.assertLessEqual(len(focus), 96)
            self.assertIn('ALT180USDT', focus)
            seen.update(focus)
            cursor = policy['nextCursor']
        self.assertEqual(seen, names)

    def test_cold_cache_batch_is_bounded_with_held_and_oldest_first(self):
        names = [f'A{i:03}USDT' for i in range(200)]
        due = due_batch(names, {}, NOW, 3600, 72, {'A199USDT'})
        self.assertEqual(len(due), 72)
        self.assertEqual(due[0], 'A199USDT')
        cache = {'A000USDT': {'fetchedAt': stamp(NOW)}}
        self.assertNotIn('A000USDT', due_batch(names, cache, NOW, 3600, 72))

    def test_real_cycle_expands_price_universe_and_accumulates_honest_coverage(self):
        class WideMarket:
            at = NOW

            def tickers(self):
                return ([quote('USDTTRY', 40, self.at), quote('BTCUSDT', 100, self.at)]
                        + [quote(f'ALT{i:03}USDT', 100, self.at) for i in range(180)])

            def candles(self, symbol):
                return candles_for(t=self.at)

            def bars(self, period, n):
                return [[0, '100', '100', '100', '100', '100',
                         int((self.at - dt.timedelta(minutes=period * (n-i))).timestamp() * 1000)]
                        for i in range(n)]

            def candles_fast(self, symbol):
                return self.bars(15, 96)

            def candles_minute(self, symbol):
                return self.bars(1, 65)

        state = fresh_state()
        execute(state, NOW - dt.timedelta(hours=2), 'ALT179USDT',
                'buy', 50, 4000, 'held coin outside leaders')
        original_orders = list(state['trades'])
        market = WideMarket()
        for i in range(3):
            market.at = NOW + dt.timedelta(minutes=2*i)
            state = cycle(state, market, market.at)
            self.assertIsNone(state['lastError'])
            self.assertEqual(state['tracked'], 181)
            self.assertEqual(state['screened'], 181)
            self.assertLessEqual(state['scanStats']['minute1m']['requested'], 96)
            self.assertIn('ALT179USDT', state['micro'])
            self.assertIn('BTCUSDT', state['histories'])
        scope = state['coverageStats']
        self.assertEqual(scope['liquidPairs'], 181)
        self.assertEqual(scope['recentMinutePairs'], 181)
        self.assertEqual(scope['minuteObservedPairs'], 96)
        self.assertEqual(len(scope['liquidSymbols']), 181)
        self.assertEqual(state['trades'], original_orders)

    def test_failed_minute_reads_are_not_counted_as_success(self):
        from backend.tests.test_paper_bot import FakeMarket
        state = cycle(fresh_state(), FakeMarket([
            quote('USDTTRY', 40), quote('BTCUSDT', 100)]), NOW)
        scope = state['coverageStats']
        self.assertEqual(scope['liquidPairs'], 1)
        self.assertEqual(scope['minuteObservedPairs'], 0)
        self.assertEqual(scope['recentMinutePairs'], 0)
        self.assertEqual(scope['fullTechnicalPairs'], 0)

    def test_nonliquid_held_chart_is_not_a_failed_liquid_chart(self):
        state = fresh_state()
        scope = snapshot(state, {}, [{'symbol': 'BTCUSDT'}],
            {'BTCUSDT': {}, 'OLDUSDT': {}},
            {'BTCUSDT': [1], 'OLDUSDT': [1]}, {'BTCUSDT', 'OLDUSDT'}, {}, NOW, 2)
        self.assertEqual(scope['minuteRequestedPairs'], 1)
        self.assertEqual(scope['minuteRequestedTotalPairs'], 2)
        self.assertEqual(scope['minuteObservedPairs'], 1)


class PublicApiHealthTests(unittest.TestCase):
    def test_rate_limit_stops_immediate_retries_and_new_requests(self):
        for code in (429, 418):
            market = Market()
            error = urllib.error.HTTPError('https://data-api.binance.vision', code,
                'rate limit', {'Retry-After': '180'}, None)
            with patch('backend.paper_bot.urllib.request.urlopen', side_effect=error) as request:
                with self.assertRaisesRegex(RuntimeError, 'Retry-After'):
                    market.tickers()
                with self.assertRaisesRegex(RuntimeError, 'backoff'):
                    market.tickers()
                self.assertEqual(request.call_count, 1)
            self.assertTrue(market.health()['rateLimited'])
            self.assertGreater(market.health()['retryAfterSeconds'], 170)

    def test_chart_budget_never_blocks_the_final_price_refresh(self):
        market = Market()
        market.begin_scan(seconds=0)

        class Response(io.BytesIO):
            status = 200
            headers = {'X-MBX-USED-WEIGHT-1M': '200'}

        with patch('backend.paper_bot.urllib.request.urlopen', return_value=Response(b'[]')) as request:
            with self.assertRaisesRegex(RuntimeError, 'budget'):
                market.candles('BTCUSDT')
            self.assertEqual(request.call_count, 0)
            self.assertEqual(market.tickers(), [])
            self.assertEqual(request.call_count, 1)
        self.assertEqual(market.health()['usedWeight1m'], 200)

    def test_backoff_persists_across_new_scheduled_processes(self):
        state = fresh_state()
        resume = NOW + dt.timedelta(minutes=30)
        state['marketBackoffUntil'] = stamp(resume)
        market = Market()
        with patch('backend.paper_bot.urllib.request.urlopen') as request:
            result = cycle(state, market, NOW)
            self.assertEqual(request.call_count, 0)
        self.assertEqual(result['marketBackoffUntil'], stamp(resume))
        self.assertEqual(result['trades'], [])
        self.assertIsNotNone(result['lastError'])


if __name__ == '__main__':
    unittest.main()
