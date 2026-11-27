"""Versioned forward experiments; never creates orders or changes the wallet.

The old momentum model remains a separate control. New hypotheses use closed
chart summaries and observed prices, not future candles. All lanes measure the
same one-hour reference horizon and assumed round-trip costs. They must earn
evidence before any future production promotion.
"""
import math
import statistics

from backend.chart_reader import read_entry
from backend.shadow_validation import record, settle, summary
from backend.relative_alpha import LANES as RELATIVE_LANES, signal as relative_signal

VERSION = "retest-reversal-v1"
LANES = ("support_reclaim", "breakout_retest", "breakdown_retest") + RELATIVE_LANES
CACHES = {"1h": "histories", "15m": "intraday", "1m": "micro"}
PERIOD_MS = {"1h": 3600000, "15m": 900000, "1m": 60000}


def valid(x):
    return isinstance(x, (float, int)) and not isinstance(x, bool) and math.isfinite(x)


def prices(state, symbol, cache):
    seq = state.get(cache, {}).get(symbol, {}).get("prices", [])
    if not isinstance(seq, list) or not all(valid(x) and x > 0 for x in seq):
        return []
    return seq


def reports(state, symbol, now):
    out = read_entry(state, symbol, "buy", now).get("timeframes", {})
    for tf in CACHES:
        row = out.get(tf, {})
        end = row.get("endMs")
        # Fetch timestamp alone cannot establish candle freshness.
        if not valid(end) or not 0 <= now.timestamp()*1000-end <= 2*PERIOD_MS[tf]:
            return {}
    return out


def _retest_classify(state, symbol, price, now):
    """Distinct causal setups. Score ranks hypotheses, not expected return."""
    chart = reports(state, symbol, now)
    if not chart or not valid(price) or price <= 0:
        return []
    h, f, m = (chart[tf] for tf in ("1h", "15m", "1m"))
    seq = prices(state, symbol, "micro")
    if len(seq) < 30 or abs(price/seq[-1]-1) > .003:
        return []
    rsi, volume, atr = (m.get(k) for k in ("rsi", "volumeRatio", "atrPct"))
    if not all(valid(x) for x in (rsi, volume, atr)) or volume < 1.15 or atr <= 0:
        return []
    tol = max(.0008, min(.003, atr/100))
    old = seq[-25:-5]
    recent = seq[-5:-1]
    last = seq[-1]
    upper, lower = max(old), min(old)
    support = f.get("supportTry")
    resistance = f.get("resistanceTry")
    out = []
    if (h["trend"] != "DOWN" and f["trend"] != "DOWN"
            and valid(support) and support > 0
            and min(recent) <= support*(1+tol)
            and last > support*(1+tol) and last > seq[-2]
            and price > support and 42 <= rsi <= 62
            and m["pattern"] in ("LOWER_WICK", "BULL_BODY")
            and valid(resistance) and resistance > price*1.006):
        out.append(("support_reclaim", "BUY", volume))
    # Break, return to the old level, then close away from it. The last
    # candle cannot establish both the break and the later retest.
    if (h["trend"] == "UP" and f["trend"] != "DOWN"
            and recent[0] > upper*(1+tol/2)
            and min(recent[1:]) <= upper*(1+tol)
            and min(recent[1:]) >= upper*(1-tol)
            and last > upper*(1+tol/2) and last > seq[-2]
            and upper < price < upper*(1+3*tol)
            and 48 <= rsi <= 65 and not m["bullTrap"]):
        out.append(("breakout_retest", "BUY", volume))
    if (h["trend"] == "DOWN" and f["trend"] != "UP"
            and recent[0] < lower*(1-tol/2)
            and max(recent[1:]) >= lower*(1-tol)
            and max(recent[1:]) <= lower*(1+tol)
            and last < lower*(1-tol/2) and last < seq[-2]
            and lower*(1-3*tol) < price < lower
            and 35 <= rsi <= 52 and not m["bearTrap"]):
        out.append(("breakdown_retest", "SHORT", volume))
    return out


def classify(state, symbol, price, now):
    # Own the result list: never mutate a reused upstream result, including
    # on a later rejected candle-alignment check.
    out = list(_retest_classify(state, symbol, price, now))
    if symbol == "BTCUSDT" or not valid(price) or price <= 0:
        return out
    chart = reports(state, symbol, now)
    benchmark = reports(state, "BTCUSDT", now)
    if not chart or not benchmark:
        return out
    if chart["15m"].get("endMs") != benchmark["15m"].get("endMs"):
        return out
    coin = prices(state, symbol, "intraday")
    btc = prices(state, "BTCUSDT", "intraday")
    if len(coin) < 65 or len(btc) < 65 or abs(price/coin[-1]-1) > .004:
        return out
    # Old cache entries are ignored until refreshed with actual timestamps.
    cache = state.get("intraday", {})
    ct = cache.get(symbol, {}).get("endTimesMs", [])
    bt = cache.get("BTCUSDT", {}).get("endTimesMs", [])
    if len(ct) != len(coin) or len(bt) != len(btc):
        return out
    ct, bt = ct[-65:], bt[-65:]
    if ct != bt or any(y-x != 900000 for x,y in zip(ct,ct[1:])):
        return out
    found = relative_signal(coin, btc)
    if found:
        out.append(found)
    return out


def correlation(state, a, b, now):
    """Aligned last 24 fifteen-minute close-to-close returns; no stale pairs."""
    x, y = (reports(state, s, now).get("15m", {}) for s in (a, b))
    if not x or not y or x["endMs"] != y["endMs"]:
        return None
    p, q = (prices(state, s, "intraday")[-25:] for s in (a, b))
    if len(p) != 25 or len(q) != 25:
        return None
    u, v = ([r[i]/r[i-1]-1 for i in range(1, 25)] for r in (p, q))
    try:
        return statistics.correlation(u, v)
    except statistics.StatisticsError:
        return None


def entry_veto(state, symbol, side, now):
    """Live-only safety veto; doesn't authorize a trade or block any exit."""
    if not state.get("ohlcvReaderActive"):
        return None
    chart = reports(state, symbol, now)
    if not chart:
        return "Taze kapalı mumlarla giriş doğrulanamadı"
    m = chart["1m"]
    rsi = m.get("rsi")
    if not valid(rsi):
        return "RSI verisi doğrulanamadı"
    if side == "short" and (rsi < 35 or m.get("pattern") == "LOWER_WICK"):
        return "SHORT dip kovalamasi / dönüş riski"
    if side == "buy" and (rsi > 70 or m.get("pattern") == "UPPER_WICK"):
        return "SPOT tepe kovalamasi / dönüş riski"
    held = state.get("shorts" if side == "short" else "holdings", {})
    # A single SHORT exposure until a separately validated new policy exists.
    if side == "short" and held:
        return "SHORT aynı yön yığılma engeli"
    for other in held:
        corr = correlation(state, symbol, other, now)
        if corr is not None and corr >= .80:
            return "Mevcut pozisyonla yüksek 15dk korelasyon"
    return None



# Fixed hypotheses, expressed as NET percentage of entry notional, after
# the same assumed costs as the baseline. No intrabar fills are invented.
EXIT_MODELS = {"net1_stop1": (1.0, 1.0), "net2_stop1": (2.0, 1.0),
               "net3_stop2": (3.0, 2.0)}


def observe_exit_paths(book, latest, now):
    import datetime as dt
    evidence = book.setdefault("forwardEvidence", {"pending": [], "completed": []})
    history = book.setdefault("observedExitPathsV1", [])
    for sample in evidence.get("pending", []):
        path = sample.get("exitPathV1")
        if not isinstance(path, dict):
            continue  # Never reconstruct earlier missing observations.
        try:
            started = dt.datetime.fromisoformat(sample["at"].replace("Z", "+00:00"))
            age = (now-started).total_seconds()
            entry = sample["entryPriceTry"]
            price = latest.get(sample["symbol"], {}).get("priceTry")
        except (KeyError, ValueError, TypeError):
            continue
        if age <= 0:
            continue
        if age > 4800:
            for name in EXIT_MODELS:
                if name not in path["closed"]:
                    path["closed"].append(name)
                    history.append({"model": name, "reason": "NO_QUOTE",
                                    "netPct": None, "symbol": sample["symbol"]})
            continue
        if not valid(price) or price <= 0 or not valid(entry) or entry <= 0:
            continue
        direction = 1 if sample["action"] == "BUY" else -1
        net = direction * (price/entry-1)*100 - .3
        for name, (target, stop) in EXIT_MODELS.items():
            if name in path["closed"]:
                continue
            reason = ("TARGET" if net >= target else "STOP" if net <= -stop
                      else "TIMEOUT" if age >= 3600 else None)
            if reason:
                path["closed"].append(name)
                history.append({"model": name, "reason": reason,
                                "netPct": round(net, 5), "symbol": sample["symbol"],
                                "at": now.isoformat(), "elapsedMinutes": round(age/60, 2)})
    del history[:-1080]


def exit_path_summary(book):
    history = book.get("observedExitPathsV1", [])
    report = {}
    for name, (target, stop) in EXIT_MODELS.items():
        rows = [r for r in history if r["model"] == name]
        values = [r["netPct"] for r in rows if valid(r.get("netPct"))]
        report[name] = {"samples": len(values), "netTargetPct": target,
            "netStopPct": stop, "targetHits": sum(r["reason"] == "TARGET" for r in rows),
            "stopHits": sum(r["reason"] == "STOP" for r in rows),
            "timeouts": sum(r["reason"] == "TIMEOUT" for r in rows),
            "missingQuotes": sum(r["reason"] == "NO_QUOTE" for r in rows),
            "avgNetPct": round(statistics.mean(values), 4) if values else None,
            "winRatePct": round(100*sum(x>0 for x in values)/len(values), 2) if values else None}
    return report


def observe(state, latest, now):
    """Independent per-lane queues, no portfolio, order, or gate overrides."""
    if not state.get("ohlcvReaderActive"):
        return {"version": VERSION, "status": "NO_CHART_DATA", "lanes": {}}
    lab = state.setdefault("strategyLabV1", {})
    candidates = {k: [] for k in LANES}
    for symbol, quote in latest.items():
        if quote.get("entryEligible") is False:
            continue
        for lane, action, score in classify(state, symbol, quote.get("priceTry"), now):
            candidates[lane].append({"symbol": symbol, "action": action,
                "score": score, "setupTag": lane})
    output = {}
    for lane in LANES:
        book = lab.setdefault(lane, {})
        observe_exit_paths(book, latest, now)
        settle(book, latest, now)
        choices = sorted(candidates[lane], key=lambda x: (-x["score"], x["symbol"]))
        # Try other eligible symbols if the leader is already being observed.
        # record caps new observations at three and enforces per-symbol cooldown.
        new = record(book, latest, {"candidates": choices[:8]}, now)
        if new:
            for sample in book["forwardEvidence"]["pending"][-new:]:
                sample["exitPathV1"] = {"closed": []}
        stats = summary(book)
        rows = book["forwardEvidence"]["completed"]
        distinct = len({r["symbol"] for r in rows})
        # Diagnostic only, not an authorization. Sample clusters remain.
        output[lane] = {"samples": stats["samples"], "pending": stats["pending"],
            "avgNetPct": stats["avgNetPct"], "winRatePct": stats["winRatePct"],
            "medianNetPct": stats["medianNetPct"], "distinctSymbols": distinct,
            "expiredNoQuote": stats["expiredNoQuote"], "new": new,
            "candidates": len(choices), "top": choices[:3],
            "exitPathModels": exit_path_summary(book)}
    return {"version": VERSION, "status": "RESEARCH_ONLY", "lanes": output,
        "exitPathVersion": "observed-first-trigger-v1",
        "horizonMinutes": 60, "assumedRoundTripCostPct": .3,
        "automaticOrder": False, "promotionRequiresIndependentValidation": True}
