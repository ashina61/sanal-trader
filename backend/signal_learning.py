"""Observed 1-minute momentum and online paper outcome calibration.

No synthetic fills or future candles. A strategy's selection bias changes only
after completed virtual trades with a recorded entry setup.
"""
import math


def minute_signal(closes, mark):
    if not isinstance(closes, list) or len(closes) < 35:
        return None
    tail = closes[-35:]
    if not all(isinstance(v, (float, int)) and math.isfinite(v) and v > 0
               for v in tail):
        return None
    if not isinstance(mark, (int, float)) or not math.isfinite(mark) or mark <= 0:
        return None
    if abs(mark / tail[-1] - 1) > .045:
        return None
    def change(n):
        return 100 * (mark / closes[-(n + 1)] - 1)
    steps = [mark] + closes[-5:]
    upside = sum(steps[i] > steps[i+1] for i in range(5))
    prior = closes[-21:-1]
    breakout = mark > max(prior) * 1.0008
    breakdown = mark < min(prior) * .9992
    return {
        "momentum5": change(5),
        "momentum15": change(15),
        "momentum30": change(30),
        "upBars5": upside,
        "downBars5": 5 - upside,
        "breakout": breakout,
        "breakdown": breakdown,
    }


def setup_for(signal, side):
    if signal is None:
        return "hourly"
    if side == "buy":
        return "breakout" if signal["breakout"] else "trend"
    return "breakdown" if signal["breakdown"] else "trend"


def signal_bias(state, side, setup):
    """Conservative online prior, zero weight until five realized outcomes."""
    key = ("spot" if side == "buy" else "short") + ":" + setup
    data = state.get("signalStats", {}).get(key, {})
    count = data.get("closed", 0)
    if not isinstance(count, int) or count < 5:
        return 0.0
    roi = data.get("meanRoi", 0)
    if not isinstance(roi, (int, float)) or not math.isfinite(roi):
        return 0.0
    return max(-.20, min(.20, float(roi) * 14)) * min(1, count / 20)


def record_open(state, symbol, side, setup, amount, at):
    """Persist setup metadata at fill time, not when evaluating candidates."""
    if side not in ("buy", "short") or amount <= 0:
        return
    state.setdefault("openSignals", {})[symbol] = {
        "side": side, "setup": setup, "amountTry": round(amount, 6),
        "openedAt": at,
    }


def record_close(state, symbol, realized):
    """Update only from an actually completed virtual close; no replays."""
    open_data = state.setdefault("openSignals", {}).pop(symbol, None)
    if not isinstance(open_data, dict) or not math.isfinite(realized):
        return
    amount = open_data.get("amountTry")
    if not isinstance(amount, (float, int)) or amount <= 0:
        return
    side = open_data.get("side")
    if side not in ("buy", "short"):
        return
    setup = open_data.get("setup", "hourly")
    key = ("spot" if side == "buy" else "short") + ":" + setup
    stats = state.setdefault("signalStats", {}).setdefault(key, {
        "closed": 0, "wins": 0, "netTry": 0.0, "meanRoi": 0.0
    })
    count = stats["closed"]
    roi = max(-1.0, min(1.0, realized / amount))
    # No backfilled or fabricated returns: these fields are derived only
    # from a real virtual close and the recorded entry amount.
    stats["meanRoi"] = ((stats["meanRoi"] * count + roi) / (count + 1))
    stats["closed"] = count + 1
    stats["wins"] += int(realized > 0)
    stats["netTry"] = round(stats["netTry"] + realized, 6)
