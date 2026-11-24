import unittest
from backend.ai_brain import apply_ai_brain

BASE = {
    "action": "BUY", "symbol": "BTCUSDT", "amountTry": 50.0, "score": .9,
    "reason": "technical buy",
    "order": ("BTCUSDT", "buy", 50.0, "technical buy"),
    "marketRegime": "YÜKSELİŞ",
    "aiChoices": [
        {"symbol": "BTCUSDT", "action": "BUY", "amountTry": 50.0, "score": .9},
        {"symbol": "ETHUSDT", "action": "SHORT", "amountTry": 30.0, "score": .8},
    ],
}
STATE = {"cashTry": 400.0, "equityTry": 650.0, "todayOrders": 2,
         "holdings": {}, "shorts": {}}


class AiBrainTests(unittest.TestCase):

    def test_groq_request_has_explicit_non_urllib_user_agent(self):
        from unittest.mock import patch
        from backend.ai_brain import _ask_groq
        import io
        import json

        class Response:
            status = 200
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self, maximum):
                body = {"choices": [{"message": {"content":
                    '{"decision":"WAIT","reason":"test only"}'}}]}
                return json.dumps(body).encode()

        def fake_urlopen(req, timeout):
            self.assertNotIn("Python-urllib",
                req.get_header("User-agent") or "")
            self.assertEqual(req.get_header("User-agent"),
                             "SanalTraderPaperBot/1.0")
            self.assertTrue(req.get_header("Authorization").startswith("Bearer "))
            return Response()

        with patch("backend.ai_brain.urllib.request.urlopen", side_effect=fake_urlopen):
            decision = _ask_groq({"candidates": []}, "fake", "openai/gpt-oss-20b")
        self.assertEqual(decision["decision"], "WAIT")

    def test_unconfigured_rules_continue(self):
        plan, meta = apply_ai_brain(BASE, STATE)
        self.assertEqual(plan["order"], BASE["order"])
        self.assertEqual(meta["status"], "NOT_CONFIGURED")

    def test_ai_gets_actual_pnl_costs_and_only_approved_candidates(self):
        state = dict(STATE, performance={
            "netTry": -2.4, "returnPct": -0.37
        }, trades=[
            {"symbol": "BTCUSDT", "side": "sell", "realizedPnlTry": -1.5},
            {"symbol": "ETHUSDT", "side": "buy", "realizedPnlTry": 0.0},
        ])
        captured = {}
        def respond(context):
            captured.update(context)
            return {"decision": "WAIT", "reason": "fees too high"}
        plan, meta = apply_ai_brain(BASE, state, "fake", ask_fn=respond)
        self.assertEqual(meta["status"], "WAIT")
        self.assertEqual(captured["roundTripPaperFeePct"], .2)
        self.assertEqual(captured["closedOutcomeSampleSize"], 1)
        self.assertEqual(captured["observedPerformance"]["netTry"], -2.4)
        self.assertEqual(len(captured["recentClosedOutcomes"]), 1)
        self.assertEqual(captured["recentClosedOutcomes"][0]["netPnlTry"], -1.5)
        self.assertEqual(len(captured["candidates"]), 2)
        self.assertIsNone(plan["order"])

    def test_ai_can_pick_only_valid_alternative(self):
        plan, meta = apply_ai_brain(
            BASE, STATE, "fake",
            ask_fn=lambda ctx: {"decision": "TRADE", "symbol": "ETHUSDT",
                                "action": "SHORT", "reason": "bearish candidate"})
        self.assertEqual(plan["order"][0:3], ("ETHUSDT", "short", 30.0))
        self.assertEqual(meta["status"], "TRADE")

    def test_ai_selected_candidate_keeps_its_own_risk_ticket_audit(self):
        plan = dict(BASE,
            sizeAudit={"mode": "STANDARD_ENTRY", "amountTry": 50.0},
            aiChoices=[
                {"symbol": "BTCUSDT", "action": "BUY",
                 "amountTry": 50.0, "score": .9,
                 "sizeAudit": {"mode": "STANDARD_ENTRY", "amountTry": 50.0}},
                {"symbol": "ETHUSDT", "action": "BUY",
                 "amountTry": 85.0, "score": 1.2,
                 "chartReading": {
                     "verdict": "CONFIRMED", "blocked": False,
                     "reasons": ["15dk ve 1s olumlu"], "timeframes": {}},
                 "sizeAudit": {
                     "mode": "QUALIFIED_SPOT_BREAKOUT_RISK_BUDGET",
                     "amountTry": 85.0,
                     "estimatedLossAtStopTry": 2.635}},
            ])
        chosen, meta = apply_ai_brain(
            plan, STATE, "fake",
            ask_fn=lambda _: {"decision": "TRADE", "symbol": "ETHUSDT",
                              "action": "BUY", "reason": "approved in tests"})
        self.assertEqual(meta["status"], "TRADE")
        self.assertEqual(chosen["order"][:3], ("ETHUSDT", "buy", 85.0))
        self.assertEqual(chosen["sizeAudit"]["amountTry"], 85.0)
        self.assertEqual(chosen["sizeAudit"]["estimatedLossAtStopTry"], 2.635)
        self.assertEqual(chosen["chartReadout"]["verdict"], "CONFIRMED")

    def test_wait_is_valid(self):
        plan, meta = apply_ai_brain(
            BASE, STATE, "fake", ask_fn=lambda ctx: {
                "decision": "WAIT", "reason": "not convinced"})
        self.assertIsNone(plan["order"])
        self.assertEqual(meta["status"], "WAIT")

    def test_invalid_or_failing_ai_cannot_invent_trade(self):
        for responder in (
            lambda ctx: {"decision": "TRADE", "symbol": "SCAMUSDT",
                         "action": "BUY"},
            lambda ctx: {"decision": "TRADE", "symbol": "ETHUSDT",
                         "action": "BUY"},
            lambda ctx: {"decision": "SELL"},
            lambda ctx: 33,
        ):
            plan, meta = apply_ai_brain(BASE, STATE, "fake", ask_fn=responder)
            self.assertEqual(plan["order"], BASE["order"])
            self.assertEqual(meta["status"], "FALLBACK")

    def test_rotation_sell_is_not_misreported_as_stop_loss(self):
        plan = dict(BASE, action="SELL",
                    order=("BTCUSDT", "sell", 48, "Portföy rotasyonu"),
                    rotation={"exit": "BTCUSDT", "candidate": "ETHUSDT"})
        result, meta = apply_ai_brain(plan, STATE, "fake", ask_fn=lambda _: 0)
        self.assertEqual(result["order"], plan["order"])
        self.assertEqual(meta["status"], "ROTATION_EXIT")

    def test_risk_reduction_reports_discretionary_technical_exit(self):
        plan = dict(BASE, action="SELL",
                    reason="Risk azaltımı: zayıf momentum",
                    order=("BTCUSDT", "sell", 25.0, "Risk azaltımı: zayıf momentum"))
        result, meta = apply_ai_brain(
            plan, STATE, "fake", ask_fn=lambda _: 0)
        self.assertEqual(result["order"], plan["order"])
        self.assertEqual(meta["status"], "RISK_REDUCTION")
        self.assertEqual(meta["provider"], "Rules")

    def test_protective_exits_bypass_ai(self):
        plan = dict(BASE, action="SELL", order=("BTCUSDT", "sell", 48, "stop"))
        result, meta = apply_ai_brain(plan, STATE, "fake", ask_fn=lambda _: 0)
        self.assertEqual(result["order"], plan["order"])
        self.assertEqual(meta["status"], "PROTECTIVE_EXIT")


if __name__ == "__main__":
    unittest.main()
