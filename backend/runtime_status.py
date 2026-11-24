"""Observed cycle diagnostics. A heartbeat is never a successful market scan."""
import datetime as dt
import time


def iso(value):
    return value.astimezone(dt.timezone.utc).isoformat(
        timespec="seconds").replace("+00:00", "Z")


def elapsed(t, timestamp):
    try:
        previous = dt.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        return max(0.0, (t - previous).total_seconds())
    except (AttributeError, ValueError, TypeError):
        return None


def start(t, last_success=None):
    return {
        "schema": 1, "mode": "scheduled-rest", "phase": "STARTED",
        "startedAt": iso(t), "completedAt": None,
        "previousSuccessAt": last_success, "marketObservedAt": None,
        "secondsSinceSuccess": elapsed(t, last_success),
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

    plan = state.get("decisionPlan") or {}
    status["action"] = plan.get("action", "WAIT")
    status["terminalCode"] = {
        "PAUSED": "BOT_PAUSED", "SKIPPED": "DUPLICATE_WINDOW",
        "ERROR": "CYCLE_ERROR", "PROTECTED": "PROTECTIVE_EXIT",
    }.get(phase, "WAIT" if status["action"] == "WAIT" else "ORDER_EXECUTED")
    # A skipped heartbeat retains the old plan, not a new decision.
    if phase in ("SKIPPED", "PAUSED", "ERROR"):
        status["action"] = "WAIT"
    status["rejectReasons"] = dict(plan.get("rejectReasons") or {}) if status["scanCompleted"] else {}
    status["candidates"] = len(plan.get("candidates") or []) if status["scanCompleted"] else 0
