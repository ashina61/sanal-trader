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

    def test_ai_can_pick_only_valid_alternative(self):
        plan, meta = apply_ai_brain(
            BASE, STATE, "fake",
            ask_fn=lambda ctx: {"decision": "TRADE", "symbol": "ETHUSDT",
                                "action": "SHORT", "reason": "bearish candidate"})
        self.assertEqual(plan["order"][0:3], ("ETHUSDT", "short", 30.0))
        self.assertEqual(meta["status"], "TRADE")

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

    def test_protective_exits_bypass_ai(self):
        plan = dict(BASE, action="SELL", order=("BTCUSDT", "sell", 48, "stop"))
        result, meta = apply_ai_brain(plan, STATE, "fake", ask_fn=lambda _: 0)
        self.assertEqual(result["order"], plan["order"])
        self.assertEqual(meta["status"], "PROTECTIVE_EXIT")


if __name__ == "__main__":
    unittest.main()
