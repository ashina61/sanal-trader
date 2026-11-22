import datetime as dt
import unittest

from backend.paper_bot import (
    assess_decision, cycle, execute, fresh_state, pick, fast_momentum,
)
from backend.short_positions import open_short
from backend.tests.test_paper_bot import (
    FakeMarket, NOW, candles_for, quote,
)


def market_prices(series, pair="BTCUSDT"):
    state = fresh_state()
    state["histories"][pair] = {
        "prices": series,
        "fetchedAt": NOW.isoformat(),
    }
    latest = {pair: {
        "priceTry": series[-1], "change24h": (
            (series[-1] / series[-25] - 1) * 100
        ),
    }}
    return state, latest


class AutonomousDecisionTests(unittest.TestCase):
    def test_rising_market_selects_spot_buy_and_explains_why(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "BUY")
        self.assertEqual(plan["marketRegime"], "YÜKSELİŞ")
        self.assertEqual(plan["symbol"], "BTCUSDT")
        self.assertGreater(plan["score"], .55)
        self.assertIn("SPOT AL", plan["reason"])
        self.assertGreater(plan["amountTry"], 5)
        self.assertTrue(plan["candidates"])
        self.assertEqual(pick(state, quotes, NOW), plan["order"])

    def test_falling_market_selects_1x_short_not_spot_buy(self):
        state, quotes = market_prices([200 - i * .5 for i in range(168)])
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "SHORT")
        self.assertEqual(plan["marketRegime"], "DÜŞÜŞ")
        self.assertIn("1x SHORT", plan["reason"])
        self.assertNotIn("BTCUSDT", state["holdings"])

    def test_sideways_or_missing_history_waits_instead_of_fabricating(self):
        state, quotes = market_prices([100.0] * 168)
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "WAIT")
        self.assertIsNone(plan["order"])
        self.assertIn("trend/momentum", plan["reason"])
        state["histories"].clear()
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")

    def test_old_history_or_large_price_discrepancy_cannot_open_new_risk(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        state["histories"]["BTCUSDT"]["fetchedAt"] = (
            NOW - dt.timedelta(hours=3)).isoformat()
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")
        state["histories"]["BTCUSDT"]["fetchedAt"] = NOW.isoformat()
        quotes["BTCUSDT"]["priceTry"] *= 1.4
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")

    def test_spot_sell_still_works_on_existing_position_without_new_entry(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        execute(state, NOW - dt.timedelta(hours=2), "BTCUSDT", "buy", 50, 100,
                "older spot buy")
        quotes["BTCUSDT"]["priceTry"] = 90
        state["todayOrders"] = 8
        state["peakEquityTry"] = 800
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "SELL")
        self.assertIn("zarar kes", plan["reason"])

    def test_short_cover_outweighs_new_bearish_short_signal(self):
        state, quotes = market_prices([200 - i * .5 for i in range(168)])
        open_short(state, NOW - dt.timedelta(hours=2), "BTCUSDT", 60, 100,
                   "previous short")
        quotes["BTCUSDT"]["priceTry"] = 111
        state["todayOrders"] = 8
        state["peakEquityTry"] = 800
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "COVER")
        self.assertIn("zarar kes", plan["reason"])


    def _near_capacity_rotation_setup(self):
        weak = [100 + i * .3 for i in range(168)]
        for j in range(8):
            weak[-8 + j] = weak[-9] - (j + 1) * .15
        strong = [100 + i * .6 for i in range(168)]
        flat = [100.0] * 168
        state = fresh_state()
        latest = {}
        for pair in ("BTCUSDT", "ETHUSDT", "BNBUSDT",
                     "ADAUSDT", "SOLUSDT", "XRPUSDT"):
            series = weak if pair == "BTCUSDT" else flat
            state["histories"][pair] = {
                "fetchedAt": NOW.isoformat(), "prices": series,
            }
            latest[pair] = {"priceTry": series[-1], "change24h": 0}
            execute(state, NOW - dt.timedelta(hours=2),
                    pair, "buy", 78, series[-1], "previous paper entry")
        state["histories"]["AVAXUSDT"] = {
            "fetchedAt": NOW.isoformat(), "prices": strong,
        }
        latest["AVAXUSDT"] = {"priceTry": strong[-1], "change24h": 8}
        return state, latest

    def test_near_full_wallet_can_sell_fading_spot_for_stronger_signal(self):
        state, quotes = self._near_capacity_rotation_setup()
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "SELL")
        self.assertEqual(plan["symbol"], "BTCUSDT")
        self.assertEqual(plan["rotation"]["candidate"], "AVAXUSDT")
        self.assertIn("Portföy rotasyonu", plan["reason"])
        self.assertEqual(len(state["trades"]), 6)

    def test_no_rotation_without_verified_stronger_entry_or_extra_fees(self):
        state, quotes = self._near_capacity_rotation_setup()
        state["histories"]["AVAXUSDT"]["prices"] = [100.0] * 168
        quotes["AVAXUSDT"]["priceTry"] = 100.0
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "WAIT")
        self.assertEqual(state["todayOrders"], 6)
        self.assertEqual(len(state["trades"]), 6)

    def test_rotation_never_ignores_daily_limit_or_existing_rotation(self):
        state, quotes = self._near_capacity_rotation_setup()
        state["todayOrders"] = 16
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")
        state["todayOrders"] = 6
        state["trades"].insert(0, {
            "at": NOW.isoformat(), "reason": "Portföy rotasyonu: prior",
            "symbol": "ETHUSDT", "side": "sell",
        })
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")

    def test_rotation_does_not_realize_large_paper_loss_to_force_a_trade(self):
        state, quotes = self._near_capacity_rotation_setup()
        quotes["BTCUSDT"]["priceTry"] *= .975
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")

    def test_long_trailing_protection_on_observed_peak_pullback(self):
        state, latest = market_prices([100 + i * .4 for i in range(168)])
        execute(state, NOW - dt.timedelta(hours=3), "BTCUSDT",
                "buy", 50, 100, "previous long")
        latest["BTCUSDT"]["priceTry"] = 103
        state["peakMarksTry"] = {"BTCUSDT": 106}
        plan = assess_decision(state, latest, NOW)
        self.assertEqual(plan["action"], "SELL")
        self.assertIn("takip eden kâr koruması", plan["reason"])

    def test_short_trailing_protection_on_observed_low_reversal(self):
        state, latest = market_prices([200 - i * .5 for i in range(168)])
        open_short(state, NOW - dt.timedelta(hours=3), "BTCUSDT",
                   50, 100, "previous short")
        latest["BTCUSDT"]["priceTry"] = 97
        state["troughMarksTry"] = {"BTCUSDT": 95}
        plan = assess_decision(state, latest, NOW)
        self.assertEqual(plan["action"], "COVER")
        self.assertIn("takip eden kâr koruması", plan["reason"])

    def test_eight_orders_no_longer_blocks_valid_new_entry(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        state["todayOrders"] = 8
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "BUY")

    def test_actual_intraday_weakness_blocks_fast_buy(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        now = quotes["BTCUSDT"]["priceTry"]
        bars = [now * (1.015 - i * .0001) for i in range(96)]
        # Last fast bar is lower than four bars before, matched to ticker.
        state["intraday"] = {"BTCUSDT": {
            "fetchedAt": NOW.isoformat(), "prices": bars}}
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "WAIT")
        self.assertIn("15dk ters trend", plan["rejectReasons"])

    def test_fast_momentum_rejects_unverified_candles(self):
        self.assertIsNone(fast_momentum([100.0]*8, 100))
        self.assertIsNone(fast_momentum([100.0]*96, 125))
        found = fast_momentum([100 + i *.05 for i in range(96)], 105.0)
        self.assertIsNotNone(found)
        self.assertGreater(found["momentum1h"], 0)

    def test_full_portfolio_can_release_declining_held_coin(self):
        # No fake profits: one observed weak 4h trend + a modest real loss
        # may free capital before the hard -6% stop.
        weak = [100 + i * .10 for i in range(168)]
        state = fresh_state()
        quotes = {}
        for pair in ("BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT",
                     "ADAUSDT", "XRPUSDT"):
            state["histories"][pair] = {
                "prices": weak, "fetchedAt": NOW.isoformat(),
            }
            execute(state, NOW - dt.timedelta(hours=3),
                    pair, "buy", 78, weak[-1], "existing paper long")
            quotes[pair] = {"priceTry": weak[-1], "change24h": 1}
        # Cut a monitored weak position at -0.8%, with an observed
        # fast 4h decline. No forced replacement order.
        pair = "ADAUSDT"
        entry = state["holdings"][pair]["costTry"] / state["holdings"][pair]["quantity"]
        current = entry * .992
        quotes[pair]["priceTry"] = current
        state["intraday"][pair] = {
            "fetchedAt": NOW.isoformat(),
            "prices": [current * (1.035 - i * .0003) for i in range(95)] +
                      [current * 1.0001],
        }
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "SELL")
        self.assertEqual(plan["symbol"], pair)
        self.assertIn("Risk azaltımı:", plan["reason"])
        self.assertEqual(len(state["holdings"]), 6)

    def test_exposure_relief_requires_confirmed_weakness_and_cooldown(self):
        weak = [100 + i * .1 for i in range(168)]
        state = fresh_state()
        quotes = {}
        for pair in ("BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT",
                     "ADAUSDT", "XRPUSDT"):
            state["histories"][pair] = {
                "prices": weak, "fetchedAt": NOW.isoformat(),
            }
            execute(state, NOW - dt.timedelta(hours=3),
                    pair, "buy", 78, weak[-1], "existing paper long")
            quotes[pair] = {"priceTry": weak[-1], "change24h": 1}
        # Even if exposure is full, favorable 15m data means WAIT, not churn.
        self.assertEqual(assess_decision(state, quotes, NOW)["action"], "WAIT")

    def test_money_or_risk_limit_selects_wait(self):
        state, quotes = market_prices([100 + i * .4 for i in range(168)])
        state["todayOrders"] = 16
        self.assertIn("16", assess_decision(state, quotes, NOW)["reason"])
        state["todayOrders"] = 0
        state["peakEquityTry"] = 1000
        self.assertIn("gerilemesi", assess_decision(state, quotes, NOW)["reason"])

    def test_decision_plan_is_persisted_without_fake_trade(self):
        ticks = [quote("USDTTRY", 40), quote("BTCUSDT", 100)]
        data = {"BTCUSDT": candles_for(price=100)}
        result = cycle(fresh_state(), FakeMarket(ticks, data), NOW)
        self.assertIsNone(result["lastError"])
        plan = result["decisionPlan"]
        self.assertIn(plan["action"], {"BUY", "SELL", "SHORT", "COVER", "WAIT"})
        self.assertIn("marketRegime", plan)
        self.assertNotIn("order", plan)
        if plan["action"] == "WAIT":
            self.assertEqual(result["trades"], [])
        else:
            self.assertEqual(len(result["trades"]), 1)

    def test_feed_failure_does_not_reuse_old_action_or_open_order(self):
        state, _ = market_prices([100 + i * .4 for i in range(168)])
        state["decisionPlan"] = {
            "action": "BUY", "symbol": "BTCUSDT",
        }
        result = cycle(state, FakeMarket([quote("BTCUSDT", 100)]), NOW)
        self.assertIsNotNone(result["lastError"])
        self.assertEqual(result["decisionPlan"]["action"], "WAIT")
        self.assertEqual(result["trades"], [])

    def test_no_trade_report_gives_checkable_rejection_reasons(self):
        state, quotes = market_prices([100.0] * 168)
        plan = assess_decision(state, quotes, NOW)
        self.assertEqual(plan["action"], "WAIT")
        self.assertEqual(plan["screened"], 1)
        self.assertEqual(plan["reviewed"], 1)
        self.assertEqual(plan["rejectReasons"].get("Zayıf 6s momentum"), 1)
        self.assertIn("En sık neden", plan["reason"])
        self.assertEqual(state["trades"], [])

    def test_mover_scan_includes_liquid_coin_outside_top_36(self):
        ticks = [quote("USDTTRY", 40)]
        for i in range(45):
            item = quote(f"COIN{i:02d}USDT", 10,
                         volume=50_000_000 - i * 1_000_000)
            if i == 44:
                item["openPrice"] = "20"  # -50% 24h mover
            ticks.append(item)
        result = cycle(fresh_state(), FakeMarket(ticks), NOW)
        self.assertIsNone(result["lastError"])
        self.assertEqual(result["tracked"], 45)
        self.assertGreater(result["screened"], 36)
        self.assertEqual(result["decisionPlan"]["universe"], 45)
        self.assertEqual(result["decisionPlan"]["historyPairs"], 0)
        self.assertEqual(result["trades"], [])

    def test_duplicate_cycle_does_not_erase_prior_decision(self):
        state, quotes = market_prices([100.0] * 168)
        state["lastSuccessAt"] = NOW.isoformat()
        state["lastDecision"] = "Önceki doğrulanmış karar"
        state["decisionPlan"] = {"action": "WAIT", "reason": "Önceki sebep"}
        after = cycle(state, FakeMarket([]), NOW + dt.timedelta(seconds=90))
        self.assertEqual(after["lastDecision"], state["lastDecision"])
        self.assertEqual(after["decisionPlan"], state["decisionPlan"])
        self.assertEqual(after["trades"], [])
        self.assertEqual(after["cycles"], state["cycles"] + 1)


if __name__ == "__main__":
    unittest.main()
