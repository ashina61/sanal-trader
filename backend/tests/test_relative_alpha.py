import math
import unittest
from unittest.mock import patch
from backend import relative_alpha as alpha
from backend import strategy_lab as lab
from backend.adaptive_execution import lane_evidence
import datetime as dt


def prices(returns):
    p = [100.0]
    for r in returns:
        p.append(p[-1]*math.exp(r/100))
    return p


class RelativeAlphaTests(unittest.TestCase):
    def fixture(self, direction):
        market = [.25*math.cos(i*.31) for i in range(59)] + [0]*5
        residual = [.30*math.sin(i*.7) for i in range(59)] + [-.5*direction]*4+[.25*direction]
        return prices([x+y for x,y in zip(market,residual)]), prices(market)

    def test_directional_signals_and_no_benchmark_variance(self):
        c,b = self.fixture(1)
        self.assertEqual(alpha.signal(c,b)[:2], ("relative_reclaim","BUY"))
        c,b = self.fixture(-1)
        self.assertEqual(alpha.signal(c,b)[:2], ("relative_fade","SHORT"))
        self.assertIsNone(alpha.signal(c,[100]*65))
        self.assertIsNone(alpha.signal(c[:-1],b))

    def test_alignment_required_and_fresh_lane_has_no_authority(self):
        c,b = self.fixture(1)
        now = dt.datetime(2026,11,27,tzinfo=dt.timezone.utc)
        times = [int(now.timestamp()*1000)-900000*i for i in reversed(range(65))]
        state = {"intraday":{"ALTUSDT":{"prices":c,"endTimesMs":times},
                            "BTCUSDT":{"prices":b,"endTimesMs":times}}}
        with patch.object(lab,"_retest_classify",return_value=[]), patch.object(lab,"reports",return_value={"15m":{"endMs":times[-1]}}):
            self.assertEqual(lab.classify(state,"ALTUSDT",c[-1],now)[0][:2],("relative_reclaim","BUY"))
            state["intraday"]["ALTUSDT"]["endTimesMs"] = times[:-1]+[times[-1]-1]
            self.assertEqual(lab.classify(state,"ALTUSDT",c[-1],now),[])
        self.assertFalse(lane_evidence({}, "relative_reclaim", now)["ready"])
        self.assertEqual(lane_evidence({}, "relative_fade", now)["action"],"SHORT")

    def test_replay_does_not_fill_on_signal_bar(self):
        data={"BTCUSDT":{i*900000:100 for i in range(500)},
              "ALTUSDT":{i*900000:100 if i%10 != 5 else 130 for i in range(500)}}
        with patch.object(alpha,"signal",return_value=None):
            report=alpha.replay(data)
        self.assertTrue(report["nextCloseEntry"])
        self.assertEqual(report["lanes"]["relative_reclaim"]["holdout"]["samples"],0)
        data["ALTUSDT"].pop(200*900000)
        with self.assertRaises(ValueError):
            alpha.replay(data)


if __name__=="__main__":
    unittest.main()
