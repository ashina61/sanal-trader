"""Free RSS intelligence and honest market-context feedback tests."""
import datetime as dt
import unittest

from backend.context_learning import (
    context_key, adjustment, record_entry, record_exit,
)
from backend.market_breadth import market_breadth
from backend.news_radar import (
    parse_rss, news_snapshot, entry_alert, classify,
)
from backend.paper_bot import assess_decision, fresh_state
from backend.tests.test_paper_bot import NOW


def rss(title, published, url="https://www.coindesk.com/markets/test"):
    return ('<rss><channel><item><title>' + title +
            '</title><link>' + url + '</link><pubDate>' +
            published + '</pubDate></item></channel></rss>').encode()


def valid_item(title, source="CoinDesk", minutes_ago=10, url=None):
    at = NOW - dt.timedelta(minutes=minutes_ago)
    row = {
        "title": title, "source": source,
        "url": url or "https://www.coindesk.com/markets/test",
        "publishedAt": at.isoformat().replace("+00:00", "Z"),
        "categories": classify(title)[0],
        "symbols": classify(title)[1],
        "broad": classify(title)[2],
    }
    return row


class NewsContextTests(unittest.TestCase):
    def test_news_title_must_be_fresh_valid_source_and_real_link(self):
        stamp = (NOW - dt.timedelta(minutes=15)).strftime(
            "%a, %d %b %Y %H:%M:%S GMT")
        ok = parse_rss(rss("Solana exploit reported", stamp), "CoinDesk", NOW)
        self.assertEqual(len(ok), 1)
        self.assertIn("SOLUSDT", ok[0]["symbols"])
        self.assertEqual(ok[0]["categories"], ["hack"])
        self.assertEqual(parse_rss(
            rss("Solana exploit reported", stamp, url="https://evil.example/hack"),
            "CoinDesk", NOW), [])
        stale = (NOW - dt.timedelta(days=2)).strftime(
            "%a, %d %b %Y %H:%M:%S GMT")
        self.assertEqual(parse_rss(rss("Solana exploit", stale), "CoinDesk", NOW), [])

    def test_direct_coins_only_block_new_entries_not_every_coin(self):
        snap = news_snapshot([valid_item("Solana exploit reported")], NOW)
        self.assertEqual(len(entry_alert(snap, "SOLUSDT", NOW)), 1)
        self.assertEqual(entry_alert(snap, "BTCUSDT", NOW), [])
        self.assertEqual(entry_alert(snap, "SOLUSDT",
                                     NOW + dt.timedelta(hours=3)), [])

    def test_market_wide_alert_requires_two_publishers(self):
        first = valid_item("Crypto exchange bankruptcy shocks crypto market")
        snap = news_snapshot([first], NOW)
        self.assertEqual(entry_alert(snap, "ETHUSDT", NOW), [])
        second = valid_item(
            "Crypto exchange bankruptcy shakes cryptocurrency exchange market",
            source="Cointelegraph")
        snap = news_snapshot([first, second], NOW)
        self.assertTrue(entry_alert(snap, "ETHUSDT", NOW))

    def test_news_blocks_unverified_entry_but_not_market_quote_reads(self):
        state = fresh_state()
        series = [100 + i * .4 for i in range(168)]
        state["histories"]["BTCUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": series,
        }
        latest = {"BTCUSDT": {"priceTry": series[-1]}}
        self.assertEqual(assess_decision(state, latest, NOW)["action"], "BUY")
        state["newsPulse"] = news_snapshot([
            valid_item("Bitcoin exchange hack reported")], NOW)
        blocked = assess_decision(state, latest, NOW)
        self.assertEqual(blocked["action"], "WAIT")
        self.assertIn("Yakın tarihli olumsuz haber uyarısı",
                      blocked["rejectReasons"])
        self.assertEqual(state["trades"], [])

    def test_learning_only_updates_after_real_closed_trade(self):
        state = fresh_state()
        k = context_key("buy", "YÜKSELİŞ", 4.0)
        self.assertEqual(adjustment(state, k), 0)
        for i in range(3):
            symbol = "TEST" + str(i)
            record_entry(state, symbol, k, 50, NOW.isoformat())
            self.assertEqual(adjustment(state, k), 0)
            record_exit(state, symbol, -1)
        data = state["contextStats"][k]
        self.assertEqual(data["closed"], 3)
        self.assertEqual(data["wins"], 0)
        self.assertLess(adjustment(state, k), 0)
        self.assertEqual(record_exit(state, "NOT_OPEN", 25), None)
        self.assertEqual(state["contextStats"][k]["closed"], 3)

    def test_market_breadth_counts_real_quotes_without_fake_forecast(self):
        summary = market_breadth({
            "BTCUSDT": {"change24h": 2.5},
            "ETHUSDT": {"change24h": -1.5},
            "ADAUSDT": {"change24h": 0.0},
            "FAKE": {"change24h": float("nan")},
        })
        self.assertEqual(summary["tracked"], 3)
        self.assertEqual((summary["up"], summary["down"], summary["flat"]),
                         (1, 1, 1))
        self.assertAlmostEqual(summary["medianChange24hPct"], 0)
        self.assertEqual(summary["leaders"][0]["symbol"], "BTCUSDT")

    def test_learning_key_separates_short_and_volatility(self):
        self.assertNotEqual(context_key("short", "DÜŞÜŞ", 6),
                            context_key("buy", "DÜŞÜŞ", 6))
        self.assertNotEqual(context_key("buy", "YÜKSELİŞ", 3),
                            context_key("buy", "YÜKSELİŞ", 7))
        self.assertIsNone(context_key("sell", "YÜKSELİŞ", 4))


if __name__ == "__main__":
    unittest.main()
