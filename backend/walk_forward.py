"""Chronological, no-lookahead BTC/altcoin research backtest.

Uses real CLOSED public Binance 15-minute bars and hourly aggregates. It is a
PROXY for the production strategy: live 1-minute confirmation, venue spreads,
order-book liquidity and real execution are NOT reproduced. No live portfolio
is read or modified, and no strategy optimization is performed on the holdout.
"""
import argparse
import datetime as dt
import json
import math
import statistics
import urllib.parse
import urllib.request

from backend.paper_bot import API, indicators, fast_momentum
from backend.shadow_validation import COST_PCT

INTERVAL_MS = 15 * 60 * 1000
HORIZON_BARS = 4  # 1 hour (no overlapping simulated positions per symbol)
HISTORY_BARS = 4 * 65  # hourly model needs 60+ prior completed 1h candles
HOLDOUT_FRACTION = 0.30
MINIMUM_BARS = 400
DEFAULT_SYMBOLS = ("BTCUSDT", "ETHUSDT", "SOLUSDT")
MAX_MARKET_CANDLES = 1000
TARGET_TOTAL_CANDLES = 3000  # roughly one month of genuine 15m history


def clean_klines(rows, now_ms):
    if not isinstance(rows, list):
        raise ValueError("Market candle payload is not a list")
    items = []
    for row in rows:
        if not isinstance(row, list) or len(row) < 7:
            continue
        try:
            end = int(row[6])
            price = float(row[4])
        except (ValueError, TypeError, OverflowError):
            continue
        if (end > now_ms or end <= 0 or
                end % INTERVAL_MS != INTERVAL_MS - 1 or
                not math.isfinite(price) or price <= 0):
            continue
        items.append((end, price))
    items.sort()
    unique = []
    for end, price in items:
        if unique and end == unique[-1][0]:
            unique[-1] = (end, price)
        else:
            unique.append((end, price))
    return unique


def fetch_klines(symbol, now=None, request=None):
    if not isinstance(symbol, str) or not symbol.endswith("USDT") or not symbol.isalnum():
        raise ValueError("Invalid public spot symbol")
    now = now or dt.datetime.now(dt.timezone.utc)
    all_rows = []
    end_time = None
    for _page in range(math.ceil(TARGET_TOTAL_CANDLES / MAX_MARKET_CANDLES)):
        params = {"symbol": symbol, "interval": "15m",
                  "limit": MAX_MARKET_CANDLES}
        if end_time is not None:
            params["endTime"] = end_time
        uri = API + "/api/v3/klines?" + urllib.parse.urlencode(params)
        if request is not None:
            page = request(uri)
        else:
            req = urllib.request.Request(uri, headers={
                "Accept": "application/json",
                "User-Agent": "SanalTraderHistoricalResearch/1.0",
            })
            with urllib.request.urlopen(req, timeout=15) as response:
                raw = response.read(1_500_001)
            if len(raw) > 1_500_000:
                raise ValueError("Historical market payload too large")
            page = json.loads(raw)
        if not isinstance(page, list):
            raise ValueError("Invalid page of historical candles")
        all_rows.extend(page)
        if len(page) < MAX_MARKET_CANDLES:
            break
        try:
            oldest_open = min(int(bar[0]) for bar in page
                              if isinstance(bar, list) and len(bar) >= 7)
        except (ValueError, TypeError):
            raise ValueError("Invalid historical pagination boundary")
        if end_time is not None and oldest_open >= end_time:
            raise ValueError("Non-advancing historical pagination")
        end_time = oldest_open - 1
    bars = clean_klines(all_rows, int(now.timestamp() * 1000))
    if len(bars) < MINIMUM_BARS:
        raise ValueError("Not enough closed historical candles for " + symbol)
    return bars

def _hourly_at(prices, i, times):
    # Include only genuinely ended hourly bars, not 15m prices observed in
    # the future relative to the decision time.
    hour_end = 60 * 60 * 1000 - 1
    return [prices[j] for j in range(i + 1)
            if times[j] % (60 * 60 * 1000) == hour_end][-168:]


def proxy_signal(prices, btc_prices, times, i):
    if i < HISTORY_BARS or i >= len(prices):
        return None
    if times[i] % (60 * 60 * 1000) != (60 * 60 * 1000 - 1):
        return None
    hourly = _hourly_at(prices, i, times)
    btc_hourly = _hourly_at(btc_prices, i, times)
    if len(hourly) < 60 or len(btc_hourly) < 60:
        return None
    tech = indicators(hourly)
    btc = indicators(btc_hourly)
    fast = fast_momentum(prices[max(0, i-95):i+1], prices[i])
    if not tech or not btc or not fast or tech["volatility"] > 7.5:
        return None
    # This approximates the existing 1h + 15m confirmed production entry.
    # We intentionally exclude news, 1m bars and AI. They cannot be
    # reconstructed from a single historical 15m feed.
    if (tech["direction"] == "up" and tech["score"] >= .75
            and .65 <= tech["momentum6"] <= 5.0
            and fast["momentum1h"] >= .15
            and fast["momentum4h"] >= .6
            and fast["momentum1h"] <= 1.8
            and fast["momentum4h"] <= 5
            and btc["direction"] != "down"):
        return "BUY"
    if (tech["direction"] == "down" and tech["score"] <= -.75
            and -5.0 <= tech["momentum6"] <= -.65
            and fast["momentum1h"] <= -.15
            and fast["momentum4h"] <= -.6
            and fast["momentum1h"] >= -1.8
            and fast["momentum4h"] >= -5
            and btc["direction"] != "up"):
        return "SHORT"
    return None


def _describe(trades):
    net = [x["netPct"] for x in trades]
    return {
        "observations": len(trades),
        "wins": sum(x > 0 for x in net),
        "winRatePct": round(100 * sum(x > 0 for x in net) / len(net), 2) if net else None,
        "meanNetPct": round(statistics.mean(net), 4) if net else None,
        "medianNetPct": round(statistics.median(net), 4) if net else None,
        "sumNetPct": round(sum(net), 4) if net else None,
        "spotSignals": sum(x["side"] == "BUY" for x in trades),
        "shortSignals": sum(x["side"] == "SHORT" for x in trades),
        "sufficientSample": len(trades) >= 30,
    }


def replay(symbol, prices_by_time, btc_by_time):
    """One-hour non-overlapping hypothetical outcomes for ONE symbol.

    No future close enters signal computation; only at index i+4 do we
    evaluate the observed result from a signal at index i.
    """
    times = sorted(set(prices_by_time) & set(btc_by_time))
    p = [prices_by_time[t] for t in times]
    b = [btc_by_time[t] for t in times]
    if len(times) < MINIMUM_BARS:
        raise ValueError("Insufficient aligned BTC and symbol market bars")
    # Reject gappy series to avoid silently treating >1h as 1h.
    timeline = [j for j in range(1, len(times)) if times[j] - times[j-1] != INTERVAL_MS]
    if timeline:
        raise ValueError("Missing market bars; no historical replay with gaps")
    boundary = math.floor(len(times) * (1 - HOLDOUT_FRACTION))
    train = []
    holdout = []
    for i in range(HISTORY_BARS, len(times) - HORIZON_BARS):
        side = proxy_signal(p, b, times, i)
        if side is None:
            continue
        # A development outcome must not peek over the holdout boundary.
        if i < boundary and i + HORIZON_BARS >= boundary:
            continue
        gross = (p[i + HORIZON_BARS] / p[i] - 1) * (
            1 if side == "BUY" else -1)
        entry = {"atMs": times[i], "side": side,
                 "netPct": round(gross * 100 - COST_PCT, 6)}
        (train if i < boundary else holdout).append(entry)
    # Buy-and-hold comparison is for the holdout window, NOT a trading strategy.
    baseline = 100 * (p[-1] / p[boundary] - 1)
    return {
        "symbol": symbol, "aligned15mBars": len(times),
        "firstBarMs": times[0], "lastBarMs": times[-1],
        "holdoutStartsMs": times[boundary],
        "development": _describe(train),
        "holdout": _describe(holdout),
        "holdoutCoinBuyHoldPct": round(baseline, 4),
    }


def run_report(symbols=DEFAULT_SYMBOLS, now=None, get_bars=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    get_bars = get_bars or (lambda symbol: fetch_klines(symbol, now=now))
    symbols = tuple(dict.fromkeys(("BTCUSDT",) + tuple(symbols)))
    feeds = {sym: dict(get_bars(sym)) for sym in symbols}
    reports = [replay(sym, feeds[sym], feeds["BTCUSDT"]) for sym in symbols]
    holdout = [p["holdout"] for p in reports]
    n = sum(row["observations"] for row in holdout)
    weighted = sum(row["meanNetPct"] * row["observations"] for row in holdout
                   if row["meanNetPct"] is not None)
    return {
        "generatedAt": now.isoformat(timespec="seconds").replace("+00:00", "Z"),
        "status": "RESEARCH_ONLY",
        "method": "Observed closed 15m public Binance candles; completed-hour "
                  "trend proxy; 1h forward, chronological 70/30 holdout",
        "assumedRoundTripFeeAndSlippagePct": COST_PCT,
        "executionSimulationLimitations": [
            "Not identical to production: no 1m confirmation, AI, news or orderbook",
            "SHORT uses 1x spot reference, excludes funding/borrowing",
            "Only presently listed assets; survivorship bias remains",
            "Returns are normalized per independent signal, not a second wallet",
            "The holdout must not be used to fit the strategy without a new holdout",
        ],
        "holdoutTotalSignals": n,
        "holdoutWeightedMeanNetPct": round(weighted / n, 4) if n else None,
        "holdoutSufficientSample": n >= 30,
        "coins": reports,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbols", nargs="+", default=list(DEFAULT_SYMBOLS))
    parser.add_argument("--out", default="validation-report.json")
    args = parser.parse_args()
    report = run_report(tuple(args.symbols))
    with open(args.out, "w", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    print(json.dumps({
        "status": report["status"],
        "holdoutSignals": report["holdoutTotalSignals"],
        "holdoutMeanNetPct": report["holdoutWeightedMeanNetPct"],
        "sufficientSample": report["holdoutSufficientSample"],
    }))


if __name__ == "__main__":
    main()
