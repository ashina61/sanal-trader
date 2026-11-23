"""Observed paper-trade feedback by market regime and volatility.

Learns only from CLOSED virtual positions. Bayesian shrinkage prevents a
handful of wins/losses from dominating the entry engine. No price prediction
or simulated winning trade is invented.
"""
import math


def context_key(mode, regime, volatility):
    if mode not in ("buy", "short"):
        return None
    if not isinstance(volatility, (int, float)) or not math.isfinite(volatility):
        return None
    trend = ("bull" if regime == "YÜKSELİŞ" else
             "bear" if regime == "DÜŞÜŞ" else "neutral")
    noise = "low" if volatility < 5 else "high"
    return f"{mode}:{trend}:{noise}"


def adjustment(state, key):
    if not key:
        return 0.0
    bucket = (state.get("contextStats") or {}).get(key) or {}
    count = bucket.get("closed", 0)
    mean = bucket.get("meanRoi", 0.0)
    if (not isinstance(count, int) or count < 3
            or not isinstance(mean, (int, float)) or not math.isfinite(mean)):
        return 0.0
    # Not a signal by itself; just a conservative tie-breaker.
    return round(max(-.08, min(.08, mean * 5 * count / (count + 12))), 4)


def record_entry(state, symbol, key, amount, at):
    if not key or not math.isfinite(amount) or amount <= 0:
        return
    state.setdefault("openContexts", {})[symbol] = {
        "key": key, "amountTry": amount, "at": at,
    }


def record_exit(state, symbol, realized):
    active = state.setdefault("openContexts", {}).pop(symbol, None)
    if not active or not math.isfinite(realized):
        return
    amount = active.get("amountTry")
    key = active.get("key")
    if not key or not isinstance(amount, (float, int)) or not math.isfinite(amount) or amount <= 0:
        return
    stats = state.setdefault("contextStats", {}).setdefault(key, {
        "closed": 0, "wins": 0, "meanRoi": 0.0, "netTry": 0.0,
    })
    count = stats["closed"]
    roi = max(-1, min(1, realized / amount))
    stats["meanRoi"] = (stats["meanRoi"] * count + roi) / (count + 1)
    stats["closed"] += 1
    stats["wins"] += int(realized > 0)
    stats["netTry"] = round(stats["netTry"] + realized, 6)
