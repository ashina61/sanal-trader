"""Persisted retry protection and bounded diagnostics."""
import datetime as dt
import unittest
from backend.paper_bot import cycle, fresh_state, execute
from backend.tests.test_paper_bot import FakeMarket, NOW, quote


class CycleIdentityTests(unittest.TestCase):
    def test_delayed_retry_never_reads_market_or_mutates_wallet(self):
        first = cycle(fresh_state(), FakeMarket([]), NOW, run_id='123')
        class NoCalls:
            def tickers(self):
                raise AssertionError('duplicate accessed market')
        again = cycle(first, NoCalls(), NOW + dt.timedelta(hours=1), run_id='123')
        self.assertEqual(first, again)
        self.assertIsNot(first, again)

    def test_partial_protection_error_is_consumed(self):
        state = fresh_state()
        for symbol in ('BTCUSDT', 'ETHUSDT'):
            execute(state, NOW - dt.timedelta(hours=2), symbol, 'buy', 50, 4000, 'test')
        market = FakeMarket([quote('USDTTRY', 40), quote('BTCUSDT', 90)])
        result = cycle(state, market, NOW, run_id='partial')
        self.assertEqual(result['runtimeStatus']['exitOrders'], 1)
        self.assertEqual(result['runtimeStatus']['terminalCode'], 'CYCLE_ERROR')
        self.assertEqual(result, cycle(result, market, NOW + dt.timedelta(hours=1), run_id='partial'))

    def test_history_is_bounded_and_retains_trigger(self):
        state = fresh_state()
        state['enabled'] = False
        state['lastTriggerEvent'] = 'schedule'
        state['cycleHistory'] = [{}] * 288
        result = cycle(state, FakeMarket([]), NOW, run_id='new')
        self.assertEqual(len(result['cycleHistory']), 288)
        self.assertEqual(result['cycleHistory'][-1]['triggerEvent'], 'schedule')
        self.assertEqual(result['cycleHistory'][-1]['terminalCode'], 'BOT_PAUSED')
        self.assertEqual(state['cycleHistory'][-1], {})
