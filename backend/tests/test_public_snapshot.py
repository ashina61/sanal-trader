"""Read-only projection: unchanged money, history and open orders."""
import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

from backend.public_snapshot import view
from backend.paper_bot import execute, fresh_state
from backend.tests.test_paper_bot import NOW


class CompactPublicWalletTests(unittest.TestCase):
    def sample_state(self):
        s = fresh_state()
        execute(s, NOW, "BTCUSDT", "buy", 65.0, 100.0,
                "old real virtual wallet order")
        s["lastSuccessAt"] = NOW.isoformat()
        s["netLiquidationTry"] = 647.31
        s["objective"] = {"netLiquidationTry": 647.31}
        s["equityHistory"] = [
            {"at": NOW.isoformat(), "netLiquidationTry": 647.31}]
        s["decisionPlan"] = {"action": "WAIT", "chartRadar": [
            {"symbol": "BTCUSDT", "spotVerdict": "REJECTED"}]}
        s["cycleHistory"] = [{"runId": str(i), "coverageStats":
                              {"liquidSymbols": [f"ALT{j}USDT"
                                                 for j in range(120)]}}
                             for i in range(288)]
        s["histories"] = {"BTCUSDT": {"prices": list(range(160))}}
        s["micro"] = {"BTCUSDT": {"prices": list(range(60))}}
        s["forwardEvidence"] = {"completed": [
            {"symbol": "BTCUSDT", "netReturnPct": -.45}]*360}
        return s

    def test_dashboard_projection_keeps_exact_single_wallet_and_all_orders(self):
        canonical = self.sample_state()
        before = copy.deepcopy(canonical)
        public = view(canonical)
        self.assertEqual(public["cashTry"], canonical["cashTry"])
        self.assertEqual(public["netLiquidationTry"], 647.31)
        self.assertEqual(public["initialCashTry"], 650)
        self.assertEqual(public["holdings"], canonical["holdings"])
        self.assertEqual(public["trades"], canonical["trades"])
        self.assertEqual(public["equityHistory"], canonical["equityHistory"])
        self.assertEqual(public["decisionPlan"], canonical["decisionPlan"])
        self.assertEqual(canonical, before)  # no mutation of original
        for cache in ("histories", "intraday", "micro",
                      "forwardEvidence", "cycleHistory",
                      "processedRunIds"):
            self.assertNotIn(cache, public)
        self.assertEqual(public["schema"], 1)

    def test_dashboard_is_dramatically_smaller_than_canonical_history(self):
        canonical = self.sample_state()
        original_bytes = len(json.dumps(canonical).encode("utf-8"))
        display_bytes = len(json.dumps(view(canonical)).encode("utf-8"))
        self.assertLess(display_bytes, original_bytes*.10)

    def test_fail_closed_missing_schema_or_trades(self):
        canonical = self.sample_state()
        for mutation in (lambda s: s.pop("trades"),
                         lambda s: s.update(schema=2),
                         lambda s: s.update(holdings=[])):
            copy = dict(canonical)
            mutation(copy)
            with self.assertRaises(ValueError):
                view(copy)

    def test_cli_writes_new_projection_not_original_wallet_file(self):
        state = self.sample_state()
        with tempfile.TemporaryDirectory() as folder:
            full = pathlib.Path(folder)/"state.json"
            display = pathlib.Path(folder)/"public-state.json"
            full.write_text(json.dumps(state), encoding="utf-8")
            original = full.read_bytes()
            subprocess.run(
                [sys.executable, "-m", "backend.public_snapshot",
                 "--state", str(full), "--output", str(display)],
                check=True, capture_output=True, text=True)
            projection = json.loads(display.read_text(encoding="utf-8"))
            self.assertEqual(projection["trades"], state["trades"])
            self.assertNotIn("histories", projection)
            self.assertEqual(full.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
