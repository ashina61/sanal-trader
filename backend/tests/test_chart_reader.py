"""No lookahead: OHLCV interpretation and forward outcome attribution."""
import datetime as dt
import unittest

from backend.chart_reader import (
    closed_bars, summarize, read_entry, learning_summary,
)
from backend.paper_bot import assess_decision, fresh_state
from backend.tests.test_autonomous_decision import market_prices
from backend.tests.test_paper_bot import NOW


def kline(t, tf_seconds, n=80, falling=False):
    rows = []
    for i in range(n):
        end = t - dt.timedelta(seconds=(n-1-i)*tf_seconds + 10)
        price = (100.0 - i*.055 if falling
                 else 100 + i*.035 + (i%4-1.5)*.065)
        opened = price - (-.05 if falling else .025)
        high = max(opened, price)*1.0008
        low = min(opened, price)*.9992
        qv = 250000*(2 if i == n-1 else 1)
        rows.append([
            int((end-dt.timedelta(seconds=tf_seconds)).timestamp()*1000),
            str(opened), str(high), str(low), str(price), "1000",
            int(end.timestamp()*1000), str(qv),
        ])
    return rows


def frames(state, pair="BTCUSDT"):
    for tf, key, step in (
        ("1h", "histories", 3600),
        ("15m", "intraday", 900),
        ("1m", "micro", 60),
    ):
        rows = kline(NOW, step)
        bars = closed_bars(rows, NOW, 1)
        state[key][pair] = {"fetchedAt": NOW.isoformat(),
                            "prices": [b["c"] for b in bars],
                            "chart": summarize(bars, tf)}
    state["ohlcvReaderActive"] = True


class ChartReaderTests(unittest.TestCase):
    def test_strictly_closed_candles_and_invalid_future_or_high_low(self):
        rows = kline(NOW, 60, n=60)
        future = rows[-1].copy()
        future[6] = int((NOW+dt.timedelta(seconds=30)).timestamp()*1000)
        future[4] = "999999"
        bad = rows[-1].copy()
        bad[6] = rows[-1][6]+1
        bad[2] = "1"
        parsed = closed_bars(rows+[future, bad], NOW, 40, max_age=180)
        self.assertEqual(len(parsed), 60)
        self.assertLess(parsed[-1]["t"]/1000, NOW.timestamp())
        self.assertAlmostEqual(parsed[-1]["c"], float(rows[-1][4])*40)
        self.assertAlmostEqual(parsed[-1]["qv"], 500000)
        self.assertEqual(closed_bars(rows, NOW, -1), [])
        old = NOW + dt.timedelta(hours=4)
        self.assertEqual(closed_bars(rows, old, 40, max_age=180), [])

    def test_real_candle_body_volume_rsi_atr_and_support(self):
        bars = closed_bars(kline(NOW, 60), NOW, 1)
        r = summarize(bars, "1m")
        self.assertEqual(r["source"], "CLOSED_BINANCE_OHLCV")
        self.assertEqual(r["tf"], "1m")
        self.assertAlmostEqual(r["volumeRatio"], 2.0)
        self.assertGreater(r["atrPct"], 0)
        self.assertGreaterEqual(r["rsi"], 0)
        self.assertLessEqual(r["rsi"], 100)
        self.assertLess(r["supportTry"], r["resistanceTry"])
        self.assertIn(r["trend"], {"UP", "DOWN", "SIDEWAYS"})
        self.assertIsNone(summarize(bars[:20], "1m"))

    def test_1minute_failed_break_is_a_veto_not_a_fill(self):
        s = fresh_state()
        frames(s)
        # Last closed minute candle wicks *above* earlier resistance but
        # does not close over it: a precisely observed false break.
        rows = kline(NOW, 60)
        earlier_high = max(float(row[2]) for row in rows[-21:-1])
        last = rows[-1]
        last[1] = str(earlier_high * .997)
        last[2] = str(earlier_high * 1.012)
        last[3] = str(earlier_high * .985)
        last[4] = str(earlier_high * .992)
        bars = closed_bars(rows, NOW, 1)
        s["micro"]["BTCUSDT"]["chart"] = summarize(bars, "1m")
        reading = read_entry(s, "BTCUSDT", "buy", NOW)
        self.assertTrue(s["micro"]["BTCUSDT"]["chart"]["bullTrap"])
        self.assertTrue(reading["blocked"])
        self.assertEqual(reading["verdict"], "REJECTED")
        self.assertTrue(any("sahte" in reason for reason in reading["reasons"]))
        self.assertEqual(s["trades"], [])

    def test_missing_or_stale_chart_blocks_only_when_live_source_is_active(self):
        s = fresh_state()
        legacy = read_entry(s, "BTCUSDT", "buy", NOW)
        self.assertFalse(legacy["blocked"])
        self.assertEqual(legacy["verdict"], "LEGACY_TEST")
        s["ohlcvReaderActive"] = True
        unavailable = read_entry(s, "BTCUSDT", "buy", NOW)
        self.assertTrue(unavailable["blocked"])
        frames(s)
        s["intraday"]["BTCUSDT"]["fetchedAt"] = (
            NOW - dt.timedelta(hours=2)).isoformat()
        old = read_entry(s, "BTCUSDT", "buy", NOW)
        self.assertTrue(old["blocked"])
        self.assertIn("15m", old["reasons"][0])

    def test_paper_engine_blocks_unavailable_live_chart_but_research_runs(self):
        state, latest = market_prices([100 + i*.4 for i in range(168)])
        state["ohlcvReaderActive"] = True
        direct = assess_decision(state, latest, NOW)
        research = assess_decision(state, latest, NOW, research_only=True)
        self.assertEqual(direct["action"], "WAIT")
        self.assertTrue(any("Grafik filtresi" in key
                            for key in direct["rejectReasons"]))
        self.assertEqual(research["action"], "WAIT")
        self.assertTrue(research["candidates"])
        self.assertEqual(
            research["candidates"][0]["chartReading"]["verdict"], "NOT_READY")
        self.assertEqual(state["trades"], [])

    def test_chart_learning_counts_only_later_research_not_wallet_orders(self):
        state = fresh_state()
        state["forwardEvidence"]["completed"] = [
            {"chartVerdict": "CONFIRMED", "netReturnPct": .8},
            {"chartVerdict": "CONFIRMED", "netReturnPct": -.3},
            {"chartVerdict": "REJECTED", "netReturnPct": -.9},
            {"chartVerdict": "REJECTED", "netReturnPct": -.4},
            {"chartVerdict": "LEGACY_TEST", "netReturnPct": 99},
            {"chartVerdict": "MIXED", "netReturnPct": float("nan")},
        ]
        report = learning_summary(state)
        self.assertEqual(report["status"], "OBSERVING")
        self.assertEqual(report["byVerdict"]["CONFIRMED"]["samples"], 2)
        self.assertAlmostEqual(
            report["byVerdict"]["CONFIRMED"]["avgNetPct"], .25)
        self.assertEqual(report["byVerdict"]["REJECTED"]["samples"], 2)
        self.assertEqual(state["cashTry"], 650)
        self.assertEqual(state["trades"], [])


if __name__ == "__main__":
    unittest.main()
