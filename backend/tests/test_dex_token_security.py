import unittest
import urllib.error

from backend.dex_token_security import _url, inspect, review

BASE = "0x" + "a" * 40
SOL = "So11111111111111111111111111111111111111112"


class RiskTests(unittest.TestCase):
    def test_public_urls_bounded_and_validated(self):
        self.assertIn("/api/v1/token_security/8453?", _url("base", BASE))
        self.assertIn("/api/v1/solana/token_security?", _url("solana", SOL))
        with self.assertRaises(ValueError):
            _url("base", "https://attacker.invalid/anything")
        with self.assertRaises(ValueError):
            _url("arbitrum", BASE)

    def test_explicit_honeypot_and_mint_are_flagged(self):
        result = review("base", BASE, {
            BASE.lower(): {"is_honeypot": "1", "is_mintable": "1",
                           "sell_tax": ".25", "buy_tax": "0",
                           "transfer_pausable": "0"}})
        self.assertEqual(result["status"], "RISK_FLAGGED")
        self.assertTrue(any("honeypot" in x.lower() for x in result["flags"]))
        self.assertTrue(any("Satış vergisi" in x for x in result["flags"]))
        self.assertFalse(result["tokenSafetyVerified"])
        self.assertFalse(result["tradingAllowed"])

    def test_missing_fields_never_certify_safety(self):
        for data in ({}, {BASE: {}}, {BASE: {"is_honeypot": "unknown"}}):
            result = review("base", BASE, data)
            self.assertEqual(result["status"], "UNKNOWN")
            self.assertFalse(result["tokenSafetyVerified"])

    def test_zero_flags_still_only_partial_research(self):
        result = review("base", BASE, {BASE.lower(): {
            "is_honeypot": "0", "is_mintable": "0", "sell_tax": "0"
        }})
        self.assertEqual(result["status"], "PARTIAL")
        self.assertFalse(result["tradingAllowed"])
        self.assertFalse(result["tokenSafetyVerified"])

    def test_solana_mint_authority_is_warning_not_certification(self):
        result = review("solana", SOL, {SOL: {"mint_authority": SOL}})
        self.assertEqual(result["status"], "RISK_FLAGGED")
        self.assertFalse(result["tradingAllowed"])

    def test_http_unavailable_and_limit_four_research_only(self):
        pools = [{"chain": "base", "token": "0x" + f"{i:040x}",
                  "symbol": "T", "pool": "0x" + f"{j:040x}"}
                 for j, i in enumerate(range(1, 12))]
        def refused(chain, token):
            raise urllib.error.HTTPError("https://api.gopluslabs.io",
                                         429, "rate limited", {}, None)
        result = inspect(pools, fetcher=refused)
        self.assertEqual(result["checked"], 4)
        self.assertEqual(result["unknown"], 4)
        self.assertTrue(all("HTTP_429" in r["reason"]
                            for r in result["results"]))
        self.assertFalse(result["automaticOrder"])


if __name__ == "__main__":
    unittest.main()
