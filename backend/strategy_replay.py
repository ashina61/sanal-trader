"""Fixed entry-policy comparison on identical chronological market data.

Research ONLY: no wallet, capital compounding, automatic policy promotion or
exchange order. All policies share the same observed 15m-close exit model.
This is a proxy, not production's 1m/AI/news/order-book execution engine.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
import json
import math
import statistics

from backend.walk_forward import (fetch_klines, proxy_signal, INTERVAL_MS,
                                 HISTORY_BARS, MINIMUM_BARS)
from backend.shadow_validation import COST_PCT

POLICIES = ("spot_trend", "spot_breakout", "spot_pullback", "short_breakdown")
DEFAULT_SYMBOLS = ("BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT")
MAX_HOLD_BARS = 16
MIN_SAMPLES = 30


def policy_signal(policy, prices, btc, times, i):
    if policy not in POLICIES:
        raise ValueError("Unknown fixed research policy")
    base = proxy_signal(prices, btc, times, i)
    if base is None:
        return None
    mark = prices[i]
    prior = prices[i-16:i]
    if policy == "spot_trend":
        return "BUY" if base == "BUY" else None
    if policy == "spot_breakout":
        return "BUY" if base == "BUY" and mark > max(prior) * 1.0008 else None
    if policy == "short_breakdown":
        return "SHORT" if base == "SHORT" and mark < min(prior) * .9992 else None
    # A past pullback within an hourly uptrend followed by a reclaim of
    # the prior 45-minute closes. All inputs are known at the entry timestamp.
    peak = max(prior)
    dipped = min(prices[i-4:i]) <= peak * .996
    return "BUY" if (base == "BUY" and dipped and mark < peak
                     and mark > max(prices[i-3:i])) else None


def observed_exit(prices, i, side):
    """First later observed CLOSE triggering the fixed model, never an unseen fill."""
    direction = 1 if side == "BUY" else -1
    entry = prices[i]
    best = 0.0
    for j in range(i + 1, min(len(prices), i + MAX_HOLD_BARS + 1)):
        move = direction * (prices[j] / entry - 1)
        best = max(best, move)
        reason = None
        if move <= -.045:
            reason = "observed-stop"
        elif move >= .035:
            reason = "observed-target"
        elif best >= .015 and move >= .004 and best - move >= .009:
            reason = "observed-profit-protection"
        elif j == i + MAX_HOLD_BARS:
            reason = "four-hour-timeout"
        if reason:
            return j, 100 * move - COST_PCT, reason
    # No 4h observation and no triggered exit: incomplete, not a winner.
    return None


def describe(rows):
    values = [r["netPct"] for r in rows]
    gains = sum(v for v in values if v > 0)
    losses = -sum(v for v in values if v < 0)
    return {"samples": len(values),
            "meanNetPct": round(statistics.mean(values), 4) if values else None,
            "medianNetPct": round(statistics.median(values), 4) if values else None,
            "winRatePct": round(100 * sum(v > 0 for v in values) / len(values), 2) if values else None,
            "profitFactor": round(gains / losses, 4) if losses > 0 else None,
            "sufficientSample": len(values) >= MIN_SAMPLES}


def compare(data):
    if "BTCUSDT" not in data or len(data) < 1:
        raise ValueError("Aligned BTC market data required")
    # The same timestamps and split for EVERY symbol and policy. Missing bars
    # abort the comparison; neither ffilled prices nor invented bars are used.
    times = sorted(set.intersection(*(set(rows) for rows in data.values())))
    if len(times) < MINIMUM_BARS or any(
            times[i] - times[i-1] != INTERVAL_MS for i in range(1, len(times))):
        raise ValueError("Insufficient or gappy common market window")
    boundary = math.floor(len(times) * .70)
    prices = {name: [rows[t] for t in times] for name, rows in data.items()}
    if any(not isinstance(p, (int, float)) or not math.isfinite(p) or p <= 0
           for series in prices.values() for p in series):
        raise ValueError("Invalid historical market prices")
    development = {policy: [] for policy in POLICIES}
    holdout = {policy: [] for policy in POLICIES}
    for policy in POLICIES:
        for symbol, series in prices.items():
            next_allowed = HISTORY_BARS
            for i in range(HISTORY_BARS, len(times) - 1):
                if i < next_allowed:
                    continue
                side = policy_signal(policy, series, prices["BTCUSDT"], times, i)
                if side is None:
                    continue
                exit_data = observed_exit(series, i, side)
                if exit_data is None:
                    continue
                j, net, reason = exit_data
                # Purge outcomes crossing development into holdout.
                if i < boundary <= j:
                    next_allowed = boundary
                    continue
                next_allowed = j + 1
                row = {"symbol": symbol, "side": side, "atMs": times[i],
                       "closedAtMs": times[j], "netPct": round(net, 5), "exitReason": reason}
                (development if i < boundary else holdout)[policy].append(row)
    stats = [{"policy": policy, "development": describe(development[policy]),
              "holdout": describe(holdout[policy])} for policy in POLICIES]
    train_leaders = [row for row in stats if row["development"]["sufficientSample"]
                     and row["development"]["meanNetPct"] > 0]
    chosen = max(train_leaders, key=lambda r: r["development"]["meanNetPct"], default=None)
    return {"schema": 1, "status": "RESEARCH_ONLY_NO_AUTOMATIC_PROMOTION",
            "createdAt": dt.datetime.now(dt.timezone.utc).isoformat(),
            "policies": stats, "symbols": sorted(data),
            "commonBars": len(times), "firstBarMs": times[0], "lastBarMs": times[-1],
            "holdoutStartsMs": times[boundary], "developmentFraction": .70,
            "developmentLeader": chosen["policy"] if chosen else None,
            "developmentLeaderHoldout": chosen["holdout"] if chosen else None,
            "assumedRoundTripCostPct": COST_PCT,
            "exitModel": "15m observed closes; stop -4.5%, target +3.5%, profit protection, 4h timeout",
            "limitations": ["No second wallet or portfolio return is calculated",
                "15m price proxy excludes production 1m confirmation, news and AI",
                "Current fixed symbol basket has selection/survivorship bias",
                "Correlated signals and multiple policies require fresh forward validation",
                "No real spread, order book, SHORT borrow or funding represented",
                "Observed close exit prices are not guaranteed execution prices"]}


def run_report(symbols=DEFAULT_SYMBOLS, get_bars=fetch_klines):
    symbols = sorted(set(symbols) | {"BTCUSDT"})
    if len(symbols) > 12:
        raise ValueError("Bounded research basket limited to 12 symbols")
    with ThreadPoolExecutor(max_workers=min(6, len(symbols))) as pool:
        series = list(pool.map(get_bars, symbols))
    report = compare({symbol: dict(bars) for symbol, bars in zip(symbols, series)})
    report["source"] = "Binance public, closed 15m klines; backend.walk_forward.fetch_klines"
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbols", nargs="+", default=list(DEFAULT_SYMBOLS))
    parser.add_argument("--out", default="strategy-comparison.json")
    args = parser.parse_args()
    report = run_report(args.symbols)
    with open(args.out, "w", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({k: report[k] for k in ("status", "commonBars", "developmentLeader", "policies")}))
