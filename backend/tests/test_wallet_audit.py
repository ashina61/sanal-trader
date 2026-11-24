import unittest
from backend.paper_bot import fresh_state, execute, assess_decision, cycle
from backend.short_positions import open_short, close_short
from backend.wallet_audit import reconcile
from backend.tests.test_paper_bot import NOW, FakeMarket, quote


class WalletAuditTests(unittest.TestCase):
    def test_mixed_positions_partial_exit_and_gap_reconcile(self):
        s = fresh_state()
        execute(s, NOW, 'BTCUSDT', 'buy', 100, 10, 'test')
        open_short(s, NOW, 'ETHUSDT', 100, 10, 'test')
        self.assertEqual(reconcile(s)['status'], 'PASS')
        execute(s, NOW, 'BTCUSDT', 'sell', 60, 12, 'partial')
        self.assertEqual(reconcile(s)['status'], 'PASS')
        close_short(s, NOW, 'ETHUSDT', 40, 'gap')
        self.assertEqual(reconcile(s)['status'], 'PASS')
        execute(s, NOW, 'BTCUSDT', 'sell', 40, 8, 'remaining')
        self.assertEqual(reconcile(s)['status'], 'PASS')

    def test_corrupt_cash_blocks_new_risk(self):
        s = fresh_state()
        s['cashTry'] += 10
        self.assertEqual(reconcile(s)['status'], 'MISMATCH')
        plan = assess_decision(s, {}, NOW)
        self.assertEqual(plan.get('reasonCode'), 'ACCOUNTING_MISMATCH')
        self.assertIsNone(plan['order'])

    def test_invalid_numeric_values(self):
        for value in (float('nan'), float('inf'), True, '650', -1):
            s = fresh_state()
            s['cashTry'] = value
            self.assertEqual(reconcile(s)['status'], 'INVALID')

    def test_mismatch_does_not_block_protective_exit(self):
        s = fresh_state()
        execute(s, NOW, 'BTCUSDT', 'buy', 50, 4000, 'test')
        s['cashTry'] += 10
        result = cycle(s, FakeMarket([quote('USDTTRY', 40),
                       quote('BTCUSDT', 90)]), NOW)
        self.assertNotIn('BTCUSDT', result['holdings'])
        self.assertEqual(result['walletAudit']['status'], 'MISMATCH')
        self.assertEqual(result['runtimeStatus']['exitOrders'], 1)
