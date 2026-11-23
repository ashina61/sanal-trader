import datetime as dt
import unittest

from backend.smart_money import evaluate, refresh

NOW = dt.datetime(2026, 11, 23, 18, 0, tzinfo=dt.timezone.utc)


def ts(offset_minutes=0):
    return (NOW + dt.timedelta(minutes=offset_minutes)).isoformat().replace("+00:00", "Z")


def addr(i):
    return "0x" + format(i, "040x")


def tx(i):
    return "0x" + format(i, "064x")


def wallet(i, **overrides):
    result = {
        "chain": "base", "address": addr(i), "ownerGroup": f"owner-{i}",
        "profit30dUsd": 900_000, "winRate30dPct": 71,
        "performanceAsOf": ts(-15), "performanceVerified": True,
        "independenceVerified": True,
    }
    result.update(overrides)
    return result


def buy(i, **overrides):
    result = {
        "chain": "base", "wallet": addr(i), "tokenAddress": addr(999),
        "symbol": "TEST", "txHash": tx(1000 + i), "side": "BUY",
        "at": ts(-10 + i), "verifiedSwap": True,
        "transferOnly": False, "newCapitalVerified": True,
        "fundingGroup": f"source-{i}",
        "safety": {
            "liquidityUsd": 350_000, "priceChange60mPct": 8,
            "lpLocked": True, "sellable": True,
            "contractSafetyVerified": True, "contractMintDisabled": True,
            "blacklistDisabled": True,
        },
    }
    result.update(overrides)
    return result


def feed():
    return {"asOf": ts(-1), "wallets": [wallet(i) for i in range(1, 5)],
            "events": [buy(i) for i in range(1, 4)]}


class SmartMoneyTests(unittest.TestCase):
    def test_three_independent_verified_buys_signal_once(self):
        first = evaluate(feed(), now=NOW)
        self.assertEqual(first["status"], "READY")
        self.assertEqual(first["walletCount"], 4)
        self.assertEqual(len(first["newSignals"]), 1)
        self.assertEqual(first["newSignals"][0]["walletCount"], 3)
        self.assertFalse(first["newSignals"][0]["automaticOrder"])
        again = evaluate(feed(), first, NOW)
        self.assertEqual(again["newSignals"], [])
        self.assertEqual(len(again["history"]), 1)

    def test_same_owner_or_funder_not_independent(self):
        data = feed()
        data["wallets"][1]["ownerGroup"] = data["wallets"][0]["ownerGroup"]
        self.assertFalse(evaluate(data, now=NOW)["newSignals"])
        data = feed()
        data["events"][1]["fundingGroup"] = data["events"][0]["fundingGroup"]
        self.assertFalse(evaluate(data, now=NOW)["newSignals"])

    def test_filters_risk_and_misrepresented_swaps(self):
        for changes in (
            {"newCapitalVerified": False},
            {"verifiedSwap": False},
            {"transferOnly": True},
            {"safety": {**buy(1)["safety"], "priceChange60mPct": 31}},
            {"safety": {**buy(1)["safety"], "liquidityUsd": 199_999}},
            {"safety": {**buy(1)["safety"], "contractMintDisabled": False}},
        ):
            data = feed()
            data["events"][0].update(changes)
            with self.subTest(changes=changes):
                self.assertEqual(evaluate(data, now=NOW)["newSignals"], [])

    def test_profit_stats_timing_and_expiry(self):
        data = feed()
        data["wallets"][0]["profit30dUsd"] = 750_000
        self.assertFalse(evaluate(data, now=NOW)["newSignals"])
        data = feed()
        data["wallets"][0]["winRate30dPct"] = 64.9
        self.assertFalse(evaluate(data, now=NOW)["newSignals"])
        data = feed()
        data["events"][0]["at"] = ts(-25)
        self.assertFalse(evaluate(data, now=NOW)["newSignals"])
        data = feed()
        data["asOf"] = ts(-6)
        self.assertEqual(evaluate(data, now=NOW)["status"], "STALE")

    def test_sells_alert_after_token_seen_without_paper_order(self):
        state = evaluate(feed(), now=NOW)
        data = feed()
        data["events"].append({**buy(1), "side": "SELL",
                               "txHash": tx(3001), "at": ts(-1)})
        updated = evaluate(data, state, NOW)
        self.assertEqual(len(updated["saleAlerts"]), 1)
        self.assertFalse(updated["saleAlerts"][0]["automaticOrder"])
        self.assertEqual(evaluate(data, updated, NOW)["saleAlerts"], [])

    def test_no_feed_never_opens_a_position_or_fakes_watches(self):
        state = refresh({}, NOW, feed_url="")
        self.assertEqual(state["status"], "NOT_CONFIGURED")
        self.assertEqual(state["walletCount"], 0)
        self.assertEqual(state["newSignals"], [])
        self.assertEqual(state["mode"], "READ_ONLY_RESEARCH")


if __name__ == "__main__":
    unittest.main()
