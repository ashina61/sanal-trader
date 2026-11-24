"""A deliberately small evidence-led SPOT experiment, not a profit claim.

The paper wallet's completed *net* positions and the independent 1-hour
observations must BOTH justify any exception to a losing broad-direction
gate. It never authorizes SHORT, ignores future prices and cannot place orders.

Rules intentionally require several distinct observed times and symbols so
one correlated tick cannot be counted as many reliable successes. The
signal history is a selected sample (not an out-of-sample strategy backtest).
"""
import datetime as dt
import math
import statistics

MIN_CLOSED_BREAKOUT = 6
MIN_FORWARD_LANE = 6
MAX_PROBE_SIZE_MULTIPLIER = .50
MAX_CONCURRENT_BREAKOUTS = 3  # Group-value and portfolio-risk caps still apply


def _finite(v):
    return (isinstance(v, (int, float)) and not isinstance(v, bool)
            and math.isfinite(v))


def _datetime(raw):
    if not isinstance(raw, str):
        return None
    try:
        value = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return value.astimezone(dt.timezone.utc) if value.tzinfo else None
    except (ValueError, OverflowError):
        return None


def _realized(state, key):
    stats = state.get("signalStats", {}).get(key, {})
    if not isinstance(stats, dict):
        stats = {}
    closed, wins, net, mean_roi = (stats.get("closed"), stats.get("wins"),
                                  stats.get("netTry"), stats.get("meanRoi"))
    if (not isinstance(closed, int) or isinstance(closed, bool)
            or closed < 0 or not isinstance(wins, int) or wins < 0
            or wins > closed or not _finite(net) or not _finite(mean_roi)):
        return {"closed": 0, "wins": 0, "netTry": 0.0,
                "meanRoiPct": None}
    return {"closed": closed, "wins": wins,
            "netTry": round(float(net), 4),
            "meanRoiPct": round(mean_roi * 100, 4)}


def _forward_lane(state, action, setup, regime, t):
    research = state.get("forwardEvidence", {})
    rows = research.get("completed", []) if isinstance(research, dict) else []
    rows = [x for x in rows if isinstance(x, dict)
            and x.get("action") == action and x.get("setup") == setup
            and x.get("regime") == regime and _finite(x.get("netReturnPct"))]
    recent = rows[-MIN_FORWARD_LANE:]
    avg = (statistics.mean(x["netReturnPct"] for x in recent)
           if recent else None)
    wins = sum(x["netReturnPct"] > 0 for x in recent)
    distinct = len({x.get("at") for x in recent
                    if isinstance(x.get("at"), str)})
    symbols = len({x.get("symbol") for x in recent
                   if isinstance(x.get("symbol"), str)})
    measured = _datetime(recent[-1].get("measuredAt")) if recent else None
    age = (t - measured).total_seconds() if measured else None
    fresh = age is not None and 0 <= age <= 3 * 3600
    return {
        "sampleSize": len(rows), "recentCount": len(recent),
        "recentAvgNetPct": round(avg, 5) if avg is not None else None,
        "recentWins": wins, "distinctScans": distinct,
        "distinctSymbols": symbols, "recentlyMeasured": fresh,
    }


def evaluate(state, action, setup, regime, now):
    """Profit-led, half-sized exception for observed SIDEWAYS SPOT breakout."""
    realized = _realized(state, "spot:breakout")
    trend = _realized(state, "spot:trend")
    short_breakdown = _realized(state, "short:breakdown")
    short_trend = _realized(state, "short:trend")
    short_net = {
        "closed": short_breakdown["closed"] + short_trend["closed"],
        "wins": short_breakdown["wins"] + short_trend["wins"],
        "netTry": round(short_breakdown["netTry"] + short_trend["netTry"], 4),
    }
    forward = _forward_lane(state, "BUY", "breakout", "YATAY", now)
    active = sum(1 for symbol, item in state.get("openSignals", {}).items()
                 if isinstance(item, dict) and item.get("side") == "buy"
                 and item.get("setup") == "breakout"
                 and symbol in state.get("holdings", {}))
    closed = realized["closed"]
    quality = (closed >= MIN_CLOSED_BREAKOUT
               and realized["wins"] / closed >= .75
               and realized["netTry"] >= 2.0
               and realized["meanRoiPct"] is not None
               and realized["meanRoiPct"] >= .75)
    prospective = (forward["sampleSize"] >= MIN_FORWARD_LANE
                   and forward["recentCount"] == MIN_FORWARD_LANE
                   and forward["recentAvgNetPct"] is not None
                   and forward["recentAvgNetPct"] >= .10
                   and forward["recentWins"] >= 3
                   and forward["distinctScans"] >= 5
                   and forward["distinctSymbols"] >= 5
                   and forward["recentlyMeasured"])
    eligible = (action == "BUY" and setup == "breakout" and regime == "YATAY"
                and quality and prospective
                and active < MAX_CONCURRENT_BREAKOUTS)
    return {
        "qualified": bool(eligible),
        "action": action, "setup": setup, "regime": regime,
        "realizedSpotBreakout": realized,
        "realizedSpotTrend": trend,
        "realizedShort": short_net,
        "forwardSidewaysBreakout": forward,
        "openBreakoutPositions": active,
        "sizeMultiplier": MAX_PROBE_SIZE_MULTIPLIER if eligible else 0.0,
        "status": "SMALL_PAPER_TRIAL" if eligible else "NOT_QUALIFIED",
        "note": "Küçük ve seçilmiş örneklem; kâr kanıtı değildir. Mevcut risk kapıları geçerlidir.",
    }


def historical_loss_guard(state, action, setup):
    """Prior completed losing trade setups cannot repeatedly drain the cash.

    This only applies after a clearly bad, albeit small, CLOSED trade sample;
    new research is unaffected. The 1-hour forward series can be used to
    review future policy but this guard never approves trades by itself.
    """
    key = ("spot:" if action == "BUY" else "short:") + setup
    data = _realized(state, key)
    n = data["closed"]
    # A small increase in win count MUST NOT reopen a setup while its
    # realized NET outcome keeps deteriorating. On 2026-11-24 the 6th
    # completed SPOT trend close changed wins from 1/4 to 2/6 despite
    # worsening cumulative net from -7.65 TRY to -9.56 TRY. The former
    # <=25% win-rate condition incorrectly cleared the loss veto.
    # A losing risk setup only resumes after its realized net / mean ROI
    # actually recover, or when explicitly redesigned and revalidated.
    losers = (n >= 4
              and data["netTry"] <= -3
              and data["meanRoiPct"] is not None
              and data["meanRoiPct"] <= -.75)
    if action == "SHORT":
        # 3/3 real paper SHORT closes lost money. With only 40 also-negative
        # future observations, demand strongly improved *fresh* prospective
        # evidence before returning to this direction.
        spot_a = _realized(state, "short:breakdown")
        spot_b = _realized(state, "short:trend")
        total = spot_a["closed"] + spot_b["closed"]
        wins = spot_a["wins"] + spot_b["wins"]
        net = spot_a["netTry"] + spot_b["netTry"]
        if total >= 3 and wins == 0 and net <= -3:
            research = state.get("forwardEvidence", {})
            rows = research.get("completed", []) if isinstance(research, dict) else []
            tail = [x["netReturnPct"] for x in rows
                    if isinstance(x, dict) and x.get("action") == "SHORT"
                    and _finite(x.get("netReturnPct"))][-24:]
            recovered = (len(tail) >= 20
                         and statistics.mean(tail) >= .25
                         and sum(x > 0 for x in tail) / len(tail) >= .60)
            losers = losers or not recovered
    return {"blocked": bool(losers), "setup": setup, "action": action,
            "actualClosed": data,
            "reason": ("Gerçekleşmiş sanal işlemler net zararlı; yeni giriş bekletiliyor"
                       if losers else "Tamamlanmış işlemlerden ek zarar freni yok")}
