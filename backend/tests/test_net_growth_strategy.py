import copy
import datetime as dt
import unittest

from backend.evidence_guard import entry_gate, strategy_gate, strategy_summary
from backend.net_objective import net_liquidation
from backend.paper_bot import fresh_state, execute, update_wallet_marks
from backend.short_positions import open_short, close_short
from backend.strategy_replay import (compare, observed_exit, policy_signal,
                                     POLICIES, MAX_HOLD_BARS)
from backend.tests.test_paper_bot import NOW
from backend.tests.test_evidence_learning import market_series


def samples(side, setup, regime, result, n):
    return [dict(action=side, setup=setup, regime=regime, netReturnPct=result)
            for _ in range(n)]


class StrategyGateTests(unittest.TestCase):
    def test_bad_trend_cannot_be_hidden_by_profitable_breakouts(self):
        state = fresh_state()
        state['forwardEvidence']['completed'] = (
            samples('BUY', 'trend', 'YÜKSELİŞ', -1, 12) +
            samples('BUY', 'breakout', 'YÜKSELİŞ', 1, 12))
        self.assertFalse(entry_gate(state, 'BUY')['blocked'])
        self.assertTrue(strategy_gate(state, 'BUY', 'trend', 'YÜKSELİŞ')['blocked'])
        self.assertFalse(strategy_gate(state, 'BUY', 'breakout', 'YÜKSELİŞ')['blocked'])
        self.assertEqual(len(strategy_summary(state)), 2)

    def test_measured_spot_lane_does_not_inherit_other_setup_losses(self):
        state = fresh_state()
        state['forwardEvidence']['completed'] = (
            samples('BUY', 'breakout', 'YÜKSELİŞ', 1, 12) +
            samples('BUY', 'trend', 'YÜKSELİŞ', -1, 12))
        self.assertTrue(entry_gate(state, 'BUY')['blocked'])
        lane = strategy_gate(state, 'BUY', 'breakout', 'YÜKSELİŞ')
        self.assertFalse(lane['blocked'])
        self.assertEqual(lane['scope'], 'setup-regime')
        # New/unmeasured setups inherit the broad guard.
        self.assertTrue(strategy_gate(state, 'BUY', 'hourly', 'YÜKSELİŞ')['blocked'])

    def test_short_retains_directional_loss_guard(self):
        state = fresh_state()
        state['forwardEvidence']['completed'] = (
            samples('SHORT', 'breakdown', 'DÜŞÜŞ', 1, 6) +
            samples('SHORT', 'trend', 'YATAY', -2, 12))
        self.assertTrue(strategy_gate(state, 'SHORT', 'breakdown', 'DÜŞÜŞ')['blocked'])


class NetObjectiveTests(unittest.TestCase):
    def test_spot_estimate_equals_actual_model_close_without_double_fees(self):
        state = fresh_state()
        execute(state, NOW, 'BTCUSDT', 'buy', 100, 100, 'test')
        latest = {'BTCUSDT': {'priceTry': 110}}
        net = net_liquidation(state, latest)
        self.assertAlmostEqual(net['netLiquidationTry'], 659.79)
        self.assertAlmostEqual(net['estimatedClosingFeesTry'], .11)
        execute(state, NOW, 'BTCUSDT', 'sell', 110, 110, 'test close')
        self.assertAlmostEqual(state['cashTry'], net['netLiquidationTry'])

    def test_short_estimate_matches_isolated_close_and_gap_cap(self):
        for mark in (90, 110, 1000):
            state = fresh_state()
            open_short(state, NOW, 'BTCUSDT', 50, 100, 'test')
            net = net_liquidation(state, {'BTCUSDT': {'priceTry': mark}})
            close_short(state, NOW, 'BTCUSDT', mark, 'test close')
            self.assertAlmostEqual(state['cashTry'], net['netLiquidationTry'])

    def test_missing_quote_clears_fresh_objective_and_never_claims_target(self):
        state = fresh_state()
        execute(state, NOW, 'BTCUSDT', 'buy', 100, 100, 'test')
        update_wallet_marks(state, {'BTCUSDT': {'priceTry': 110}}, NOW)
        self.assertIn('netLiquidationTry', state)
        update_wallet_marks(state, {}, NOW + dt.timedelta(minutes=2))
        self.assertNotIn('netLiquidationTry', state)
        self.assertEqual(state['objective']['metric'], 'unavailable')
        state['cashTry'] = 0
        state['holdings'] = {'BTCUSDT': {'quantity': 1, 'costTry': 650}}
        net = net_liquidation(state, {'BTCUSDT': {'priceTry': 1300}})
        self.assertFalse(net['targetReached'])
        self.assertLess(net['netLiquidationTry'], 1300)

    def test_new_net_history_preserves_old_mark_observations_and_wallet(self):
        state = fresh_state()
        state['equityHistory'] = [{'at': '2026-11-22T00:00:00Z', 'equityTry': 650}]
        execute(state, NOW, 'BTCUSDT', 'buy', 100, 100, 'test')
        before = copy.deepcopy((state['cashTry'], state['trades'], state['holdings']))
        update_wallet_marks(state, {'BTCUSDT': {'priceTry': 110}}, NOW)
        self.assertNotIn('netLiquidationTry', state['equityHistory'][0])
        self.assertIn('netLiquidationTry', state['equityHistory'][-1])
        self.assertAlmostEqual(state['performance']['netTry'], 9.79)
        self.assertEqual(before, (state['cashTry'], state['trades'], state['holdings']))


class StrategyReplayTests(unittest.TestCase):
    def test_future_prices_cannot_change_any_earlier_entry_policy(self):
        times, prices = market_series()
        i = 411
        changed = list(prices)
        changed[i+1:] = [1e9] * (len(prices) - i - 1)
        for policy in POLICIES:
            self.assertEqual(policy_signal(policy, prices, prices, times, i),
                             policy_signal(policy, changed, changed, times, i))

    def test_gap_stop_uses_observed_close_not_invented_threshold_price(self):
        out = observed_exit([100, 90, 95], 0, 'BUY')
        self.assertEqual(out[0], 1)
        self.assertAlmostEqual(out[1], -10.3)
        self.assertIsNone(observed_exit([100, 100.1], 0, 'BUY'))

    def test_policies_share_window_and_flat_data_never_makes_a_winner(self):
        times, prices = market_series()
        flat = dict(zip(times, [100] * len(times)))
        report = compare({'BTCUSDT': flat, 'ETHUSDT': flat})
        self.assertIsNone(report['developmentLeader'])
        self.assertEqual(report['commonBars'], len(times))
        self.assertEqual(len(report['policies']), 4)
        self.assertTrue(all(r['holdout']['samples'] == 0 for r in report['policies']))
        gappy = dict(flat)
        gappy.pop(times[400])
        with self.assertRaises(ValueError):
            compare({'BTCUSDT': flat, 'ETHUSDT': gappy})

    def test_entry_and_exit_costs_are_counted_for_four_hour_observation(self):
        out = observed_exit([100] * (MAX_HOLD_BARS + 1), 0, 'BUY')
        self.assertEqual(out[2], 'four-hour-timeout')
        self.assertAlmostEqual(out[1], -.3)


if __name__ == '__main__':
    unittest.main()
