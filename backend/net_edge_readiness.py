"""Economic readiness test for *new* simulated BUY/SHORT entries.

Cross-sectional forward observations are only 1-hour research outcomes,
not independent or reliable alpha. This is a veto, NEVER an order generator.
No assumption that zero fees, more AI prompts, or riskier bet sizes create
positive expected returns. Existing exit controls bypass the veto.

For repositories with *no* observations the legacy paper exploration still
works; once enough observed signals exist and fail economic validation,
unproven new risk is suspended while research-only candidates still collect.
"""
import datetime as dt
import math
import statistics

OBSERVED_MIN = 30
REVALIDATION_LONG = 60
REVALIDATION_SHORT = 24
LONG_MIN_NET_PCT = .15
SHORT_MIN_NET_PCT = .20
SHORT_MIN_WINS = 14
UNIQUE_SYMBOLS_MIN = 8
FRESH_SECONDS = 3 * 3600


def _measured(value):
    if not isinstance(value, str):
        return None
    try:
        moment = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return moment.astimezone(dt.timezone.utc) if moment.tzinfo else None
    except (ValueError, OverflowError):
        return None


def review(state, action, now):
    base = {
        "action": action, "blocked": False, "status": "NO_ENTRY",
        "samples": 0, "last60AvgNetPct": None,
        "last24AvgNetPct": None, "last24Positive": 0,
        "distinctSymbols": 0, "lastMeasuredAt": None,
        "costsIncluded": True, "researchContinues": True,
        "protectiveExitsUnaffected": True,
        "note": "Bu istatistikler ileride kâr garantisi değildir.",
    }
    if action not in ("BUY", "SHORT"):
        return {**base, "status": "EXIT_PRIORITY"}
    evidence = state.get("forwardEvidence", {})
    completed = evidence.get("completed", []) if isinstance(evidence, dict) else []
    rows = [r for r in completed if isinstance(r, dict)
            and r.get("action") == action
            and isinstance(r.get("netReturnPct"), (int, float))
            and not isinstance(r["netReturnPct"], bool)
            and math.isfinite(r["netReturnPct"])]
    length = len(rows)
    # The research queue retains only the last 360 signals overall.
    # In a falling market SHORT observations can crowd almost all BUY
    # observations out, e.g. 348 SHORT / 12 BUY. A mature losing wallet
    # must NOT reopen BUY risk just because its directional sample fell
    # below OBSERVED_MIN due to the shared rolling cap.
    total_completed = sum(
        isinstance(r, dict) and r.get("action") in ("BUY", "SHORT")
        and isinstance(r.get("netReturnPct"), (int, float))
        and not isinstance(r.get("netReturnPct"), bool)
        and math.isfinite(r["netReturnPct"])
        for r in completed)
    values = [float(r["netReturnPct"]) for r in rows]
    tail60 = values[-REVALIDATION_LONG:]
    tail24 = values[-REVALIDATION_SHORT:]
    avg60 = statistics.mean(tail60) if tail60 else None
    avg24 = statistics.mean(tail24) if tail24 else None
    wins24 = sum(v > 0 for v in tail24)
    distinct = len({r["symbol"] for r in rows[-REVALIDATION_LONG:]
                    if isinstance(r.get("symbol"), str) and r["symbol"]})
    measured = _measured(rows[-1].get("measuredAt")) if rows else None
    age = ((now.astimezone(dt.timezone.utc) - measured).total_seconds()
           if measured and isinstance(now, dt.datetime) and now.tzinfo else None)
    fresh = age is not None and 0 <= age <= FRESH_SECONDS
    sufficient = length >= REVALIDATION_LONG
    calibrated = (sufficient and fresh
                  and avg60 >= LONG_MIN_NET_PCT
                  and avg24 >= SHORT_MIN_NET_PCT
                  and wins24 >= SHORT_MIN_WINS
                  and distinct >= UNIQUE_SYMBOLS_MIN)
    # Research starts immediately on a fresh paper wallet. Once >=30
    # completed forward observations exist, require STRICT, fresh evidence
    # before resuming exposure. A positive latest 24 SHORT streak alone
    # cannot erase a negative last 60 sample or 3/3 realized SHORT losses.
    mature = length >= OBSERVED_MIN or total_completed >= REVALIDATION_LONG
    block = mature and not calibrated
    if block:
        status = ("INSUFFICIENT_DIRECTIONAL_EVIDENCE"
                  if length < REVALIDATION_LONG else "NO_PROVEN_NET_EDGE")
    elif calibrated:
        status = "PROVISIONAL_REVALIDATION"
    else:
        status = "INITIAL_RESEARCH"
    return {
        **base, "status": status, "blocked": block,
        "samples": length, "allDirectionsSamples": total_completed,
        "missingDirectionalSamples": max(0, REVALIDATION_LONG-length),
        "last60AvgNetPct": round(avg60, 4) if avg60 is not None else None,
        "last24AvgNetPct": round(avg24, 4) if avg24 is not None else None,
        "last24Positive": wins24, "distinctSymbols": distinct,
        "lastMeasuredAt": measured.isoformat() if measured else None,
        "fresh": fresh, "provisionallyRevalidated": calibrated,
        "note": ("Kâr avantajı doğrulanmadı: son 60 ve 24 bağımsız olmayan "
                 "ileri gözlemde net pozitiflik, güncellik ve çeşitlilik "
                 "birlikte oluşmadan yeni sanal risk açılmaz."
                 if block else "Olumlu sonuçlar kâr garantisi değildir; "
                 "tüm diğer risk denetimleri yine geçerlidir."),
    }


def snapshot(state, now):
    return {
        "BUY": review(state, "BUY", now),
        "SHORT": review(state, "SHORT", now),
        "researchContinues": True,
        "protectiveExitsUnaffected": True,
        "notAProfitForecast": True,
    }
