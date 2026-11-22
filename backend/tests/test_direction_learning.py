import unittest

from backend.paper_bot import execute, fresh_state
from backend.short_positions import (
    close_short, direction_edge, learn_closed_direction, open_short,
)
from backend.tests.test_paper_bot import NOW


class DirectionLearningTests(unittest.TestCase):
    def test_closed_short_only_enters_learning_after_real_cover(self):
        state = fresh_state()
        open_short(state, NOW, "ADAUSDT", 50, 100, "bear")
        self.assertFalse(state["directionStats"])
        close_short(state, NOW, "ADAUSDT", 90, "cover")
        history = state["directionStats"]["short"]
        self.assertEqual(history["closed"], 1)
        self.assertEqual(history["wins"], 1)
        self.assertGreater(history["realizedTry"], 0)
        self.assertEqual(direction_edge(state, "short"), 0)

    def test_long_closed_loss_is_tracked_separately(self):
        state = fresh_state()
        execute(state, NOW, "ETHUSDT", "buy", 50, 100, "long")
        execute(state, NOW, "ETHUSDT", "sell", 45, 90, "long exit")
        self.assertEqual(state["directionStats"]["long"]["closed"], 1)
        self.assertLess(state["directionStats"]["long"]["realizedTry"], 0)
        self.assertNotIn("short", state["directionStats"])

    def test_repeated_realized_results_calibrate_only_bounded_priority(self):
        state = fresh_state()
        for i in range(9):
            pair = "COIN" + str(i) + "USDT"
            open_short(state, NOW, pair, 30, 100, "bear")
            close_short(state, NOW, pair, 50, "correct bear")
        self.assertEqual(state["directionStats"]["short"]["closed"], 9)
        self.assertGreater(direction_edge(state, "short"), 0)
        self.assertLessEqual(direction_edge(state, "short"), .12)
        self.assertEqual(direction_edge(state, "long"), 0)

    def test_fabricated_nan_and_low_sample_do_not_influence_strategy(self):
        state = fresh_state()
        learn_closed_direction(state, "long", float("nan"), 50)
        self.assertNotIn("long", state["directionStats"])
        for _ in range(2):
            learn_closed_direction(state, "long", 5, 50)
        self.assertEqual(direction_edge(state, "long"), 0)


if __name__ == "__main__":
    unittest.main()
