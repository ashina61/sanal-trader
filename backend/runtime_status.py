"""Observed cycle diagnostics. A heartbeat is never a successful market scan."""
import datetime as dt
import time


def iso(value):
    return value.astimezone(dt.timezone.utc).isoformat(
        timespec="seconds").replace("+00:00", "Z")


def start(t, last_success=None):
    return {
        "schema": 1, "mode": "scheduled-rest", "phase": "STARTED",
        "startedAt": iso(t), "completedAt": None,
        "previousSuccessAt": last_success, "marketObservedAt": None,
        "oldestQuoteAt": None, "newestQuoteAt": None,
        "quotesReceived": 0, "shortlisted": 0,
        "exitCheckedAt": None, "positionsChecked": 0,
        "missingPositionQuotes": [], "exitOrders": 0,
        "scanCompleted": False, "scanCoverage": {},
        "cycleElapsedSec": None, "reason": "Kontrol başladı",
    }


def market_seen(status, latest, t):
    status["marketObservedAt"] = iso(t)
    status["shortlisted"] = len(latest)
    dates = [q["sourceAt"] for q in latest.values() if q.get("sourceAt")]
    status["oldestQuoteAt"] = min(dates) if dates else None
    status["newestQuoteAt"] = max(dates) if dates else None


def finish(status, state, phase, t, began):
    status.update({
        "phase": phase, "completedAt": iso(t),
        "cycleElapsedSec": round(time.perf_counter() - began, 3),
        "reason": (state.get("decisionPlan") or {}).get("reason", ""),
    })
    if status["scanCompleted"]:
        status["scanCoverage"] = {
            key: state.get("scanStats", {}).get(key, {})
            for key in ("hourly", "fast15m", "minute1m")
        }
