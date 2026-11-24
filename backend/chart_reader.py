"""Explain observed, fully CLOSED Binance OHLCV across 1m/15m/1h.

Rules observe EMA, RSI, ATR, swing levels, candle bodies, wicks, and
volume confirmation. This is not a trained price predictor. A chart veto
only blocks NEW virtual entries; SELL/COVER protections are unaffected.
"""
import datetime as dt
import math
import statistics

TIMEFRAMES = ("1h", "15m", "1m")
MIN_BARS = {"1h": 60, "15m": 55, "1m": 35}
MAX_AGES = {"1h": 7200, "15m": 1500, "1m": 420}


def number(v):
    if isinstance(v, bool):
        return None
    try:
        n = float(v)
        return n if math.isfinite(n) else None
    except (TypeError, ValueError, OverflowError):
        return None


def when(v):
    if not isinstance(v, str):
        return None
    try:
        t = dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
        return t.astimezone(dt.timezone.utc) if t.tzinfo else None
    except (ValueError, OverflowError):
        return None


def closed_bars(rows, now, fx, max_age=None):
    """Klines OHLC quote volume, excluding future/unclosed/invalid candles."""
    if (not isinstance(rows, list) or not isinstance(now, dt.datetime)
            or now.tzinfo is None or number(fx) is None or fx <= 0):
        return []
    values = {}
    for r in rows:
        if not isinstance(r, (list, tuple)) or len(r) < 8:
            continue
        end = number(r[6])
        o, h, l, c = [number(r[i]) for i in (1, 2, 3, 4)]
        qv = number(r[7])
        if (end is None or end <= 0 or end/1000 > now.timestamp()
                or any(x is None or x <= 0 for x in (o, h, l, c))
                or qv is None or qv < 0 or h < max(o, c)
                or l > min(o, c) or l > h):
            continue
        values[int(end)] = {"t": int(end), "o": o*fx, "h": h*fx,
                            "l": l*fx, "c": c*fx, "qv": qv}
    bars = [values[k] for k in sorted(values)][-168:]
    if max_age is not None and (not bars or
            now.timestamp()-bars[-1]["t"]/1000 > max_age):
        return []
    return bars


def ema(prices, period):
    a = 2/(period+1)
    v = statistics.mean(prices[:period])
    for p in prices[period:]:
        v += (p-v)*a
    return v


def rsi(prices, period=14):
    changes = [prices[i]-prices[i-1] for i in range(1, len(prices))]
    up = sum(max(x, 0) for x in changes[:period])/period
    down = sum(max(-x, 0) for x in changes[:period])/period
    for x in changes[period:]:
        up = (up*(period-1)+max(x, 0))/period
        down = (down*(period-1)+max(-x, 0))/period
    return (50.0 if up == down == 0 else 100.0 if down == 0
            else 100-100/(1+up/down))


def summarize(bars, timeframe):
    """Small serializable summary; raw OHLCV is discarded after parsing."""
    if (timeframe not in MIN_BARS or not isinstance(bars, list)
            or len(bars) < MIN_BARS[timeframe]):
        return None
    try:
        c = [float(b["c"]) for b in bars]
        h = [float(b["h"]) for b in bars]
        l = [float(b["l"]) for b in bars]
        o = [float(b["o"]) for b in bars]
        v = [float(b["qv"]) for b in bars]
        times = [int(b["t"]) for b in bars]
    except (KeyError, TypeError, ValueError, OverflowError):
        return None
    if (any(not math.isfinite(x) or x <= 0 for x in c+h+l+o)
            or any(not math.isfinite(x) or x < 0 for x in v)
            or any(h[i] < max(c[i], o[i]) or l[i] > min(c[i], o[i])
                   for i in range(len(c)))
            or times != sorted(set(times))):
        return None
    short, long = (8, 21) if timeframe == "1m" else (20, 50)
    fast, slow = ema(c, short), ema(c, long)
    spread = 100*(fast/slow-1)
    trend = ("UP" if spread > .07 and c[-1] >= fast else
             "DOWN" if spread < -.07 and c[-1] <= fast else "SIDEWAYS")
    high = max(h[-21:-1])
    low = min(l[-21:-1])
    bar_range = h[-1]-l[-1]
    body_ratio = abs(c[-1]-o[-1])/bar_range if bar_range > 0 else 0
    up_wick = (h[-1]-max(o[-1], c[-1]))/bar_range if bar_range else 0
    down_wick = (min(o[-1], c[-1])-l[-1])/bar_range if bar_range else 0
    background = [x for x in v[-21:-1] if x > 0]
    baseline = statistics.median(background) if background else None
    ratio = (v[-1]/baseline) if baseline is not None else None
    changes = [max(h[i]-l[i], abs(h[i]-c[i-1]), abs(l[i]-c[i-1]))
               for i in range(len(c)-14, len(c))]
    return {
        "source": "CLOSED_BINANCE_OHLCV", "tf": timeframe,
        "endMs": times[-1], "trend": trend,
        "rsi": round(rsi(c), 2), "atrPct": round(100*statistics.mean(changes)/c[-1], 3),
        "emaSpreadPct": round(spread, 3),
        "volumeRatio": round(ratio, 3) if ratio is not None else None,
        "supportTry": round(low, 8), "resistanceTry": round(high, 8),
        "breakout": c[-1] > high*1.0005 and c[-1] > o[-1] and body_ratio >= .35,
        "breakdown": c[-1] < low*.9995 and c[-1] < o[-1] and body_ratio >= .35,
        "bullTrap": h[-1] > high*1.0005 and c[-1] <= high,
        "bearTrap": l[-1] < low*.9995 and c[-1] >= low,
        "pattern": ("UPPER_WICK" if up_wick >= .55 else
                    "LOWER_WICK" if down_wick >= .55 else
                    "DOJI" if body_ratio <= .1 else
                    "BULL_BODY" if c[-1] > o[-1] else "BEAR_BODY"),
        "emaDistancePct": round(100*(c[-1]/fast-1), 3),
    }


def read_entry(state, symbol, mode, now):
    """Three timeframes; missing live OHLCV data cannot become confirmation."""
    base = {"version": "ohlcv-v1", "symbol": symbol, "side": mode,
            "verdict": "NOT_READY", "blocked": False, "reasons": [],
            "timeframes": {}, "advisoryOnly": True}
    if not isinstance(now, dt.datetime) or now.tzinfo is None:
        return {**base, "blocked": True, "reasons": ["Invalid time"]}
    reports = {}
    missing = []
    for tf, cache in (("1h", "histories"), ("15m", "intraday"), ("1m", "micro")):
        item = state.get(cache, {}).get(symbol, {})
        item = item if isinstance(item, dict) else {}
        seen = when(item.get("fetchedAt"))
        report = item.get("chart")
        age = (now-seen).total_seconds() if seen else None
        if (not isinstance(report, dict)
                or report.get("source") != "CLOSED_BINANCE_OHLCV"
                or report.get("tf") != tf
                or age is None or not 0 <= age <= MAX_AGES[tf]):
            missing.append(tf)
        else:
            reports[tf] = report
    base["timeframes"] = reports
    if missing:
        live = bool(state.get("ohlcvReaderActive"))
        return {**base, "verdict": "NOT_READY" if live else "LEGACY_TEST",
                "blocked": live,
                "reasons": ["Eksik/eski gerçek mum: "+", ".join(missing)]}
    hour, fast, minute = (reports["1h"], reports["15m"], reports["1m"])
    is_buy = mode == "buy"
    adverse = "DOWN" if is_buy else "UP"
    reasons = []
    if hour["trend"] == adverse:
        reasons.append("1s ana trend işleme ters")
    if fast["trend"] == adverse:
        reasons.append("15dk trend işleme ters")
    if (minute["bullTrap"] if is_buy else minute["bearTrap"]):
        reasons.append("1dk sahte kırılım ve fitil reddi")
    if (minute["rsi"] >= 78 if is_buy else minute["rsi"] <= 22):
        reasons.append("1dk RSI aşırı uzamış")
    if (minute["emaDistancePct"] > 2.5 if is_buy
            else minute["emaDistancePct"] < -2.5):
        reasons.append("1dk EMA'dan uzaklaşma")
    crossing = minute["breakout"] if is_buy else minute["breakdown"]
    vr = minute["volumeRatio"]
    if crossing and (vr is None or vr < 1.10):
        reasons.append("Hacimsiz 1dk kırılımı")
    aligned = sum(r["trend"] == ("UP" if is_buy else "DOWN")
                  for r in (hour, fast, minute))
    verdict = ("REJECTED" if reasons else "CONFIRMED"
               if aligned >= 2 else "MIXED")
    if not reasons:
        reasons.append("1s "+hour["trend"]+" / 15dk "+fast["trend"])
        if crossing and vr is not None and vr >= 1.25:
            reasons.append("Hacim teyitli kapanmış kırılım")
        else:
            reasons.append("1dk RSI "+str(minute["rsi"]))
    return {**base, "verdict": verdict, "blocked": bool(
                verdict == "REJECTED"), "advisoryOnly": False,
            "reasons": reasons, "timeframes": reports,
            "aligned": aligned, "volumeBreakout": bool(
                crossing and vr is not None and vr >= 1.25)}


def learning_summary(state):
    """Later observed price outcomes grouped by original chart judgment."""
    research = state.get("forwardEvidence", {})
    rows = research.get("completed", []) if isinstance(research, dict) else []
    groups = {}
    for r in rows if isinstance(rows, list) else []:
        label = r.get("chartVerdict") if isinstance(r, dict) else None
        net = r.get("netReturnPct") if isinstance(r, dict) else None
        if label not in ("CONFIRMED", "MIXED", "REJECTED", "NOT_READY"):
            continue
        if not isinstance(net, (int, float)) or not math.isfinite(net):
            continue
        groups.setdefault(label, []).append(float(net))
    return {"status": "OBSERVING" if groups else "COLLECTING",
            "horizonMinutes": 60, "costsIncluded": True,
            "byVerdict": {label: {"samples": len(xs),
                "avgNetPct": round(statistics.mean(xs), 4),
                "positivePct": round(100*sum(x > 0 for x in xs)/len(xs), 2)}
                for label, xs in groups.items()},
            "note": "İleri fiyat araştırması; sanal emir kârı değildir."}
