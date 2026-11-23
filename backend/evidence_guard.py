"""Conservative entry-risk guard from OBSERVED forward paper signals.

Not machine-learning proof of profit. Small and correlated samples cannot
establish expected return; a persistently negative sample only pauses NEW risk
in that direction. Public-price research continues to collect new observations
until the guard can be reevaluated. Protective exits are NEVER restricted.
"""
import math
import statistics

BUY_MIN = 12
SHORT_MIN = 6
WINDOW = 12


def _observations(state, side):
    research = state.get("forwardEvidence", {})
    rows = research.get("completed", []) if isinstance(research, dict) else []
    return [row["netReturnPct"] for row in rows
            if isinstance(row, dict)
            and row.get("action") == side
            and isinstance(row.get("netReturnPct"), (int, float))
            and math.isfinite(row["netReturnPct"])][-WINDOW:]


def entry_gate(state, side):
    """Reasoned guard with a rolling window, never a sell/short order."""
    if side not in ("BUY", "SHORT"):
        return {"blocked": False, "samples": 0, "reason": "not an entry"}
    values = _observations(state, side)
    n = len(values)
    required = BUY_MIN if side == "BUY" else SHORT_MIN
    mean = statistics.mean(values) if values else None
    win_rate = sum(x > 0 for x in values) / n if n else None
    # Require both negative average after assumed costs and low hit rate.
    # The window rolls automatically as later true outcomes arrive.
    blocked = (n >= required and mean <= (-.30 if side == "BUY" else -.45)
               and win_rate <= (.35 if side == "BUY" else .34))
    return {
        "blocked": bool(blocked),
        "samples": n,
        "avgNetPct": round(mean, 4) if mean is not None else None,
        "winRatePct": round(100 * win_rate, 2) if win_rate is not None else None,
        "reason": ("Recent observed forward entries have weak net outcomes; "
                   "new " + side + " risk held for fresh evidence")
                  if blocked else "Insufficient or nonnegative evidence to pause",
    }


def gate_summary(state):
    return {"BUY": entry_gate(state, "BUY"),
            "SHORT": entry_gate(state, "SHORT")}
