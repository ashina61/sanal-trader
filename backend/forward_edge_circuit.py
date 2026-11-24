"""Fail-closed *new-risk* circuit when recent forward paper signals lose money.

The inputs are post-signal PUBLIC PRICE observations, never imagined fills.
A small correlated 1-hour sample cannot prove profitable expectation. This
circuit can only PAUSE new BUY/SHORT entries, never force trades or stop exits.
Research-only candidate observations continue and can reopen the gate once
the rolling sample improves. No second wallet and no persistent parameters.
"""
import math
import statistics

MIN_OBSERVATIONS = 20
ROLLING_OBSERVATIONS = 24
NEGATIVE_AVG_THRESHOLD_PCT = -0.05
MAX_NEGATIVE_WIN_RATE_PCT = 40.0


def review(state, action):
    if action not in ("BUY", "SHORT"):
        return {"action": action, "status": "EXIT_PRIORITY",
                "blocked": False, "samples": 0}
    evidence = state.get("forwardEvidence")
    rows = evidence.get("completed", []) if isinstance(evidence, dict) else []
    values = [float(row["netReturnPct"])
              for row in rows if isinstance(row, dict)
              and row.get("action") == action
              and isinstance(row.get("netReturnPct"), (int, float))
              and not isinstance(row["netReturnPct"], bool)
              and math.isfinite(row["netReturnPct"])]
    sample = values[-ROLLING_OBSERVATIONS:]
    size = len(sample)
    mean = statistics.mean(sample) if sample else None
    hits = 100 * sum(x > 0 for x in sample) / size if sample else None
    blocked = (size >= MIN_OBSERVATIONS
               and mean <= NEGATIVE_AVG_THRESHOLD_PCT
               and hits <= MAX_NEGATIVE_WIN_RATE_PCT)
    return {
        "action": action,
        "status": ("NEGATIVE_NET_EVIDENCE" if blocked else
                   "COLLECTING" if size < MIN_OBSERVATIONS else "OBSERVING"),
        "blocked": bool(blocked),
        "samples": size,
        "avgNetPct": round(mean, 4) if mean is not None else None,
        "winRatePct": round(hits, 2) if hits is not None else None,
        "costsIncluded": True,
        "sampleWindow": ROLLING_OBSERVATIONS,
        "reason": ("Son ileri gözlemlerde ortalama net sonuç negatif; "
                   "yeni sanal giriş geçici durduruldu. "
                   "Araştırma sinyalleri izlenmeye devam eder."
                   if blocked else
                   "Yeterli yeni gözlem yok ya da net zarar freni tetiklenmedi. "
                   "Bu, kârlılık kanıtı değildir."),
    }


def snapshot(state):
    return {"BUY": review(state, "BUY"),
            "SHORT": review(state, "SHORT"),
            "researchStillActive": True,
            "newOrdersFromResearch": False}


def lane_recovery(state, action, setup, regime):
    """Qualified *limited-size* exploratory lane while broad direction loses.

    This is a narrowly-scoped opportunity to collect real paper outcomes, not
    statistical proof or permission to ignore the existing strategy risk gate.
    Small correlated samples can mislead: require both 12-sample and *recent*
    6-sample net-positive, majority-win observations. Never use unrealized
    open trades, candle hindsight, or a different wallet.
    """
    evidence = state.get("forwardEvidence")
    completed = evidence.get("completed", []) if isinstance(evidence, dict) else []
    values = [float(row["netReturnPct"])
              for row in completed if isinstance(row, dict)
              and row.get("action") == action and row.get("setup") == setup
              and row.get("regime") == regime
              and isinstance(row.get("netReturnPct"), (int, float))
              and not isinstance(row["netReturnPct"], bool)
              and math.isfinite(row["netReturnPct"])]
    tail12, tail6 = values[-12:], values[-6:]
    avg12 = statistics.mean(tail12) if tail12 else None
    avg6 = statistics.mean(tail6) if tail6 else None
    wins12 = sum(v > 0 for v in tail12)
    wins6 = sum(v > 0 for v in tail6)
    qualified = (action == "BUY" and setup == "breakout"
                 and regime == "YÜKSELİŞ"
                 and len(values) >= 20 and len(tail12) == 12
                 and avg12 >= .40 and wins12 >= 7
                 and avg6 >= .15 and wins6 >= 4)
    return {
        "action": action, "setup": setup, "regime": regime,
        "qualified": bool(qualified), "sampleSize": len(values),
        "recent12AvgNetPct": round(avg12, 4) if avg12 is not None else None,
        "recent6AvgNetPct": round(avg6, 4) if avg6 is not None else None,
        "recent12Wins": wins12, "recent6Wins": wins6,
        "sizeMultiplier": 0.5 if qualified else 0.0,
        "researchOnlyWhenUnqualified": True,
        "note": "Küçük/bağımlı örneklem; gelir veya kazanma olasılığı kanıtı değil.",
    }
