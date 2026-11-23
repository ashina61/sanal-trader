import unittest
from backend.trade_audit import summarize
from backend.net_objective import net_liquidation


def state():
    return {
        "cashTry": 100, "initialCashTry": 650,
        "holdings": {"BTCUSDT": {"quantity": .5, "costTry": 55}},
        "shorts": {}, "trades": [], "paidFeesTry": 3.2,
    }


class TradeAuditTests(unittest.TestCase):
    def test_empty_sample_never_claims_success(self):
        r = summarize(state())
        self.assertEqual(r["status"], "INSUFFICIENT_SAMPLE")
        self.assertEqual(r["closed"]["closed"], 0)
        self.assertIsNone(r["closed"]["avgNetPerCloseTry"])
        self.assertFalse(r["autonomousTradeAuthorization"])

    def test_net_outcomes_not_double_fee_deducted(self):
        s = state()
        s["trades"] = [
            {"side": "sell", "realizedPnlTry": -3, "reason": "Spot zarar kes"},
            {"side": "cover", "realizedPnlTry": 4, "reason": "SHORT kâr al:"},
            {"side": "buy", "realizedPnlTry": 0},
            {"side": "sell", "realizedPnlTry": 2, "reason": "Spot kâr al:"},
        ]
        r = summarize(s)
        self.assertEqual(r["closed"]["closed"], 3)
        self.assertEqual(r["closed"]["netRealizedTry"], 3)
        self.assertEqual(r["closed"]["profitFactor"], 2)
        self.assertEqual(r["recentLossStreak"], 1)
        self.assertEqual(r["spot"]["closed"], 2)
        self.assertEqual(r["short"]["closed"], 1)
        self.assertEqual(r["byExit"]["STOP"]["closed"], 1)
        self.assertTrue(r["feesAlreadyIncludedInRealized"])

    def test_scary_sample_not_promoted_to_profitable_model(self):
        s = state()
        s["trades"] = [
            {"side": "sell", "realizedPnlTry": -1, "reason": "stop"}
            for _ in range(10)
        ]
        r = summarize(s)
        self.assertEqual(r["status"], "RECENT_NEGATIVE")
        self.assertEqual(r["recentLossStreak"], 10)
        self.assertFalse(r["autonomousTradeAuthorization"])

    def test_exit_slippage_is_separate_scenario_not_wallet_mutation(self):
        s = state()
        objective = net_liquidation(s, {"BTCUSDT": {"priceTry": 120}})
        self.assertAlmostEqual(objective["netLiquidationTry"], 159.94)
        self.assertAlmostEqual(objective["scenarioExtraSlippageTry"], .03)
        self.assertAlmostEqual(objective["scenarioNetAfterSlippageTry"], 159.91)
        self.assertEqual(s["cashTry"], 100)


if __name__ == "__main__":
    unittest.main()
