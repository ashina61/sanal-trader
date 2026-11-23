import unittest

from backend.orderbook_pipeline import guard_plan, inspect_book, idle_trace


def plan(action="BUY", amount=50):
    side = "buy" if action == "BUY" else "short"
    return {
        "action": action, "symbol": "BTCUSDT", "amountTry": amount,
        "reason": "Entry test", "order": ("BTCUSDT", side, amount, "Entry test"),
    }


def depth(bids=None, asks=None):
    return {
        "bids": bids or [["99.95", "30"], ["99.9", "30"]],
        "asks": asks or [["100.05", "30"], ["100.1", "30"]],
    }


class BookTests(unittest.TestCase):
    def test_fair_book_all_six_stages_and_estimated_paper_price(self):
        result = inspect_book(plan(), depth(), 4000, 40)
        self.assertEqual(result["status"], "PASSED")
        self.assertTrue(result["bookObserved"])
        self.assertFalse(result["forecastCalibrated"])
        self.assertEqual([x["name"] for x in result["stages"]],
                         ["PULSE", "IMPACT", "EDGE", "SIZE", "ENTRY", "EXIT"])
        self.assertEqual(result["stages"][2]["status"], "COST_ONLY")
        self.assertGreater(result["estimatedEntryPriceTry"], 4000)

    def test_public_depth_bad_book_fails_closed(self):
        for bad in (
            None, {}, {"bids": [], "asks": []},
            depth(bids=[["104", "2"]], asks=[["102", "3"]]),
            depth(bids=[["100", "1"]], asks=[["103", "1"]]),
            depth(bids=[["99.95", "0.001"]], asks=[["100.05", "0.001"]]),
            depth(bids=[["99.95", "30"]], asks=[["102", "30"]]),
        ):
            with self.subTest(bad=bad):
                self.assertEqual(inspect_book(plan(), bad, 4000, 40)["status"],
                                 "BLOCKED")

    def test_price_disagreement_blocks_even_a_good_book(self):
        self.assertEqual(inspect_book(plan(), depth(), 3500, 40)["status"],
                         "BLOCKED")

    def test_exits_are_not_blocked_or_queried(self):
        sell = {"action": "SELL", "symbol": "BTCUSDT", "order":
                ("BTCUSDT", "sell", 50, "stop")}
        class FailingMarket:
            def depth(self, _):
                raise AssertionError("Never query depth for exits")
        selected, audit = guard_plan(sell, FailingMarket(), {}, 40)
        self.assertEqual(selected, sell)
        self.assertEqual(audit["status"], "EXIT_PRIORITY")
        self.assertEqual(audit["stages"][-1]["status"], "ARMED")

    def test_api_failure_blocks_only_new_entry(self):
        class BrokenMarket:
            def depth(self, _):
                raise ValueError("provider failed")
        original = plan()
        revised, audit = guard_plan(original, BrokenMarket(),
                                    {"BTCUSDT": {"priceTry": 4000}}, 40)
        self.assertIsNone(revised["order"])
        self.assertEqual(revised["action"], "WAIT")
        self.assertEqual(audit["status"], "BLOCKED")
        self.assertEqual(original["action"], "BUY")

    def test_real_book_uses_execution_price_and_no_new_portfolio(self):
        class MockMarket:
            def depth(self, _):
                return depth()
        revised, audit = guard_plan(plan(), MockMarket(),
                                    {"BTCUSDT": {"priceTry": 4000}}, 40)
        self.assertEqual(revised["action"], "BUY")
        self.assertEqual(revised["order"][1], "buy")
        self.assertGreater(revised["bookEntryPriceTry"], 4000)
        self.assertEqual(audit["status"], "PASSED")

    def test_unavailable_fake_provider_is_explicit_not_fake_positive(self):
        revised, trace = guard_plan(plan(), object(),
                                    {"BTCUSDT": {"priceTry": 4000}}, 40)
        self.assertEqual(revised["action"], "BUY")
        self.assertEqual(trace["status"], "UNSUPPORTED")
        self.assertFalse(trace["bookObserved"])


if __name__ == "__main__":
    unittest.main()
