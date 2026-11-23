import copy
import datetime as dt
import unittest
from urllib.parse import urlparse, parse_qs

from backend.paper_bot import fresh_state
from backend.shadow_validation import (
    COST_PCT, HORIZON_SECONDS, record, settle, summary, evidence_bias,
)
from backend.walk_forward import (
    INTERVAL_MS, clean_klines, fetch_klines, proxy_signal, replay, run_report,
)
from backend.tests.test_paper_bot import NOW


def quote(price):
    return {"BTCUSDT": {"priceTry": price}}


def approved():
    return {"marketRegime": "YÜKSELİŞ", "candidates": [
        {"symbol": "BTCUSDT", "action": "BUY",
         "score": .9, "setupTag": "breakout"}]}


def market_series(length=800, multiplier=1.001):
    # 15m candle END timestamps aligned with UTC :14:59.999, etc.
    times = [INTERVAL_MS - 1 + i * INTERVAL_MS for i in range(length)]
    closes = [100 * multiplier ** i for i in range(length)]
    return times, closes


class ForwardEvidenceTests(unittest.TestCase):
    def test_pending_is_not_profit_until_genuine_future_public_quote(self):
        state = fresh_state()
        original = copy.deepcopy((state["cashTry"], state["holdings"],
                                  state["trades"], state["equityTry"]))
        self.assertEqual(record(state, quote(100), approved(), NOW), 1)
        self.assertEqual(summary(state)["samples"], 0)
        settle(state, quote(102), NOW + dt.timedelta(minutes=59))
        self.assertEqual(summary(state)["samples"], 0)
        settle(state, quote(102), NOW + dt.timedelta(minutes=61))
        report = summary(state)
        self.assertEqual(report["samples"], 1)
        self.assertEqual(report["pending"], 0)
        self.assertAlmostEqual(report["avgNetPct"], 2 - COST_PCT)
        self.assertEqual(original, (state["cashTry"], state["holdings"],
                                    state["trades"], state["equityTry"]))
        settle(state, quote(200), NOW + dt.timedelta(minutes=62))
        self.assertEqual(summary(state)["samples"], 1)

    def test_short_prediction_uses_observed_inverse_price_move(self):
        state = fresh_state()
        p = {"marketRegime": "DÜŞÜŞ", "candidates": [{
            "symbol": "BTCUSDT", "action": "SHORT", "score": 1.1,
        }]}
        record(state, quote(100), p, NOW)
        settle(state, quote(98), NOW + dt.timedelta(minutes=62))
        self.assertAlmostEqual(summary(state)["avgNetPct"], 2 - COST_PCT)

    def test_missing_or_late_quote_cannot_backfill_profit(self):
        state = fresh_state()
        record(state, quote(100), approved(), NOW)
        settle(state, {}, NOW + dt.timedelta(minutes=66))
        self.assertEqual(summary(state)["pending"], 1)
        settle(state, quote(300), NOW + dt.timedelta(minutes=82))
        self.assertEqual(summary(state)["samples"], 0)
        self.assertEqual(summary(state)["expiredNoQuote"], 1)
        self.assertEqual(summary(state)["pending"], 0)

    def test_duplicate_candidates_not_recorded_every_two_minutes(self):
        state = fresh_state()
        record(state, quote(100), approved(), NOW)
        record(state, quote(101), approved(), NOW + dt.timedelta(minutes=2))
        self.assertEqual(summary(state)["pending"], 1)

    def test_ai_wait_and_ai_approval_are_measured_without_orders(self):
        state = fresh_state()
        plan = approved()
        record(state, quote(100), plan, NOW, ai_meta={"status": "WAIT"})
        settle(state, quote(102), NOW + dt.timedelta(minutes=61))
        self.assertEqual(summary(state)["aiWaited"]["samples"], 1)
        self.assertEqual(summary(state)["aiApproved"]["samples"], 0)
        second = NOW + dt.timedelta(minutes=65)
        plan = dict(plan, action="BUY", symbol="BTCUSDT")
        record(state, quote(100), plan, second, ai_meta={"status": "TRADE"})
        settle(state, quote(103), second + dt.timedelta(minutes=61))
        self.assertEqual(summary(state)["aiApproved"]["samples"], 1)
        self.assertEqual(summary(state)["aiWaited"]["samples"], 1)
        self.assertEqual(state["trades"], [])

    def test_thirty_real_observations_required_before_tie_break(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            {"action": "BUY", "regime": "YÜKSELİŞ", "netReturnPct": -1}
            for _ in range(29)]
        self.assertEqual(evidence_bias(state, "BUY", "YÜKSELİŞ"), 0)
        state["forwardEvidence"]["completed"].append({
            "action": "BUY", "regime": "YÜKSELİŞ", "netReturnPct": -1})
        self.assertLess(evidence_bias(state, "BUY", "YÜKSELİŞ"), 0)
        self.assertEqual(evidence_bias(state, "SHORT", "DÜŞÜŞ"), 0)
        self.assertGreaterEqual(evidence_bias(state, "BUY", "YÜKSELİŞ"), -.04)


class ChronologicalResearchTests(unittest.TestCase):
    def test_closes_only_include_truly_ended_complete_hourly_aligned_bars(self):
        rows = []
        for t in [INTERVAL_MS - 1, 2 * INTERVAL_MS - 1,
                  3 * INTERVAL_MS - 1]:
            rows.append([0, "100", "100", "100", "105", "1", t])
        rows.append([0, "100", "100", "100", "999", "1",
                     4 * INTERVAL_MS - 1])
        out = clean_klines(rows, 3 * INTERVAL_MS)
        self.assertEqual(len(out), 3)
        self.assertTrue(all(p == 105 for _, p in out))

    def test_future_candle_cannot_modify_signal_at_earlier_timestamp(self):
        ts, prices = market_series()
        i = 411  # hourly close at index 411
        original = proxy_signal(prices, prices, ts, i)
        self.assertEqual(original, "BUY")
        modified = list(prices)
        for j in range(i + 1, len(modified)):
            modified[j] = 1.0 if j % 2 == 0 else 1e10
        self.assertEqual(original, proxy_signal(modified, prices, ts, i))

    def test_trending_replay_uses_chronological_holdout_not_wallet(self):
        ts, prices = market_series()
        source = dict(zip(ts, prices))
        result = replay("BTCUSDT", source, source)
        self.assertGreater(result["development"]["observations"], 0)
        self.assertGreater(result["holdout"]["observations"], 0)
        self.assertGreater(result["holdout"]["meanNetPct"], 0)
        self.assertLess(result["holdoutStartsMs"], result["lastBarMs"])
        state = fresh_state()
        before = copy.deepcopy(state)
        report = run_report(symbols=("BTCUSDT",), get_bars=lambda _: list(source.items()))
        self.assertEqual(report["status"], "RESEARCH_ONLY")
        self.assertEqual(report["coins"][0]["symbol"], "BTCUSDT")
        self.assertEqual(before, state)

    def test_historical_fetch_pages_backward_without_duplicate_candles(self):
        now_ms = int(NOW.timestamp() * 1000)
        first_open = now_ms - 3000 * INTERVAL_MS
        rows = []
        for i in range(3000):
            opening = first_open + i * INTERVAL_MS
            rows.append([opening, "100", "100", "100", "101",
                         "1", opening + INTERVAL_MS - 1])
        calls = []
        def fake(uri):
            params = parse_qs(urlparse(uri).query)
            self.assertEqual(params["symbol"], ["BTCUSDT"])
            self.assertEqual(params["interval"], ["15m"])
            cutoff = int(params["endTime"][0]) if "endTime" in params else now_ms
            calls.append(cutoff)
            return [row for row in rows if row[0] <= cutoff][-1000:]
        bars = fetch_klines("BTCUSDT", now=NOW, request=fake)
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(bars), 3000)
        self.assertEqual(bars[0][0], first_open + INTERVAL_MS - 1)
        self.assertEqual(bars[-1][0], now_ms - 1)
        self.assertEqual(len(set(t for t, _ in bars)), 3000)

    def test_flat_market_has_no_fabricated_backtest_winners(self):
        ts, _ = market_series()
        flat = dict(zip(ts, [100] * len(ts)))
        result = replay("BTCUSDT", flat, flat)
        self.assertEqual(result["holdout"]["observations"], 0)
        self.assertIsNone(result["holdout"]["meanNetPct"])

    def test_gaps_fail_closed_instead_of_pretending_one_hour(self):
        ts, prices = market_series()
        data = dict(zip(ts, prices))
        data.pop(ts[300])
        with self.assertRaisesRegex(ValueError, "Missing market bars"):
            replay("BTCUSDT", data, data)


if __name__ == "__main__":
    unittest.main()
