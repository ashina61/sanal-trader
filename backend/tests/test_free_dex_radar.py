import datetime as dt
import urllib.error
import unittest

from backend.free_dex_radar import (PUBLIC_REQUEST_GAP_SECONDS,
    _error_label, _select_pools, analyze_batches, refresh)

NOW = dt.datetime(2026, 11, 23, 21, 0, tzinfo=dt.timezone.utc)


def at(minutes=0):
    return (NOW + dt.timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")


def evm(i):
    return "0x" + format(i, "040x")


def txn(i):
    return "0x" + format(i, "064x")


def pool(chain="base"):
    return {"chain": chain, "pool": evm(11),
            "token": evm(99), "symbol": "MEME",
            "liquidityUsd": 250000.0, "priceChange1hPct": 2.0}


def trade(i, kind="buy", minutes=-5, **extra):
    attrs = {
        "tx_from_address": evm(i), "tx_hash": txn(i),
        "block_timestamp": at(minutes), "kind": kind,
        "volume_in_usd": "250", "is_anomalous": False,
    }
    attrs.update(extra)
    return {"attributes": attrs}


def top_response():
    return {"data": [{
        "attributes": {"address": evm(11), "name": "MEME / WETH",
                       "reserve_in_usd": "250000",
                       "price_change_percentage": {"h1": "2.5"}},
        "relationships": {
            "base_token": {"data": {"id": "base_" + evm(99)}}},
    }]}


def trades(n=3):
    return {"data": [trade(i) for i in range(1, n + 1)]}


class FreeDiscoveryTests(unittest.TestCase):
    def test_pool_from_public_relationship_and_liquidity(self):
        rows = _select_pools(top_response(), "base")
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["token"], evm(99))
        too_small = top_response()
        too_small["data"][0]["attributes"]["reserve_in_usd"] = "50"
        self.assertEqual(_select_pools(too_small, "base"), [])
        large_pump = top_response()
        large_pump["data"][0]["attributes"]["price_change_percentage"]["h1"] = "31"
        self.assertEqual(_select_pools(large_pump, "base"), [])

    def test_three_distinct_senders_is_unverified_research_only(self):
        result = analyze_batches([(pool(), trades())], now=NOW)
        self.assertEqual(result["status"], "OBSERVING")
        self.assertEqual(result["observedSenders"], 3)
        self.assertEqual(result["poolsScreened"], 1)
        self.assertEqual(len(result["newClusters"]), 1)
        cluster = result["newClusters"][0]
        self.assertFalse(cluster["profitableWalletsVerified"])
        self.assertFalse(cluster["independenceVerified"])
        self.assertFalse(cluster["tokenSafetyVerified"])
        self.assertFalse(cluster["automaticOrder"])

    def test_duplicates_buys_not_counted_twice_and_replayed_deduped(self):
        same = trades()
        same["data"].append(trade(1))
        same["data"].append(trade(4, tx_hash=txn(2)))
        first = analyze_batches([(pool(), same)], now=NOW)
        self.assertEqual(first["observedSenders"], 3)
        self.assertEqual(first["tradesChecked"], 3)
        later = analyze_batches([(pool(), same)], first, NOW)
        self.assertEqual(later["newClusters"], [])
        self.assertEqual(len(later["history"]), 1)

    def test_gaps_old_anomalies_and_low_volume_are_ignored(self):
        response = {"data": [
            trade(1), trade(2, minutes=-30), trade(3, is_anomalous=True),
            trade(4, volume_in_usd="25"), trade(5, kind="sell"),
        ]}
        state = analyze_batches([(pool(), response)], now=NOW)
        self.assertEqual(len(state["newClusters"]), 0)
        self.assertEqual(state["tradesChecked"], 2)

    def test_partial_unavailable_is_explicit(self):
        partial = analyze_batches([(pool(), trades(1))], now=NOW,
                                  errors=["solana:pools:HTTPError"])
        self.assertEqual(partial["status"], "DEGRADED")
        self.assertEqual(partial["newClusters"], [])
        unavailable = analyze_batches([], now=NOW, errors=["base:HTTPError"])
        self.assertEqual(unavailable["status"], "UNAVAILABLE")
        self.assertFalse(unavailable["automaticOrder"])

    def test_http_error_status_is_persisted_for_diagnosis(self):
        exc = urllib.error.HTTPError('https://api.geckoterminal.com',
                                      429, 'Too Many Requests', {}, None)
        self.assertEqual(_error_label(exc), 'HTTP_429')

    def test_contract_review_is_research_only_and_offline_mocked(self):
        def fake_fetch(path):
            return top_response() if path.endswith("/trending_pools") else trades()
        def mocked_security(chain, token):
            return {token.lower(): {"is_honeypot": "1", "is_mintable": "0"}}
        result = refresh({}, NOW, fetcher=fake_fetch,
                         security_fetcher=mocked_security,
                         sleep=lambda _: None)
        risk = result["tokenRisk"]
        self.assertEqual(risk["checked"], 1)
        self.assertEqual(risk["riskFlagged"], 1)
        self.assertEqual(risk["results"][0]["status"], "RISK_FLAGGED")
        self.assertFalse(risk["automaticOrder"])

    def test_fake_dex_never_makes_a_second_real_network_call(self):
        def fake_fetch(path):
            return top_response() if path.endswith("/trending_pools") else trades()
        result = refresh({}, NOW, fetcher=fake_fetch,
                         sleep=lambda _: None)
        self.assertEqual(result["tokenRisk"]["status"], "NOT_TESTED")
        self.assertFalse(result["tokenRisk"]["tokenSafetyVerified"])

    def test_free_refresh_makes_real_reads_without_paid_credentials(self):
        seen = []
        delays = []
        def fake_fetch(path):
            seen.append(path)
            if path.endswith("/trending_pools"):
                if "solana" in path:
                    return {"data": []}
                return top_response()
            return trades()
        result = refresh({}, NOW, fetcher=fake_fetch, sleep=delays.append)
        self.assertEqual(result["status"], "OBSERVING")
        self.assertEqual(result["requestsMade"], 3)
        self.assertEqual(len(seen), 3)
        self.assertEqual(delays, [PUBLIC_REQUEST_GAP_SECONDS] * 2)
        self.assertEqual(len(result["newClusters"]), 1)
        cached = refresh(result, NOW + dt.timedelta(minutes=5),
                         fetcher=lambda _p: self.fail("Should use cache"),
                         sleep=lambda _n: None)
        self.assertEqual(cached, result)


if __name__ == "__main__":
    unittest.main()
