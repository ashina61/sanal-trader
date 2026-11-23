"""Forward-only validation of REAL observed paper trade signals.

No imaginary fills, no secondary wallet, and no historical rewrites. Signals
are timestamped using an observed public market mark; their hypothetical net
return is measured ONLY after a later public quote arrives within a bounded
window. An outcome is research, never a wallet transaction.
"""
import datetime as dt
import math
import statistics

HORIZON_SECONDS = 60 * 60
GRACE_SECONDS = 20 * 60
PER_SYMBOL_COOLDOWN_SECONDS = HORIZON_SECONDS
MAX_PENDING = 180
MAX_COMPLETED = 360
MAX_NEW_PER_CYCLE = 3
# Round-trip spot or 1x isolated SHORT reference. No real funding, spread or
# borrowing venue represented; conservative explicit slippage assumption.
FEE_EACH_SIDE = 0.001
SLIPPAGE_EACH_SIDE = 0.0005
COST_PCT = 100 * 2 * (FEE_EACH_SIDE + SLIPPAGE_EACH_SIDE)
MIN_SAMPLES_FOR_LEARNING = 30


def _stamp(t):
    return t.astimezone(dt.timezone.utc).isoformat(
        timespec="seconds").replace("+00:00", "Z")


def _date(value):
    if not isinstance(value, str):
        return None
    try:
        t = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return t.astimezone(dt.timezone.utc) if t.tzinfo else None
    except (ValueError, OverflowError):
        return None


def _price(latest, symbol):
    row = latest.get(symbol)
    value = row.get("priceTry") if isinstance(row, dict) else None
    return float(value) if isinstance(value, (int, float)) and math.isfinite(
        value) and value > 0 else None


def migrate(state):
    research = state.setdefault("forwardEvidence", {})
    if not isinstance(research, dict):
        raise ValueError("Invalid forward evidence data")
    for key in ("pending", "completed"):
        research.setdefault(key, [])
        if not isinstance(research[key], list):
            raise ValueError("Invalid forward evidence list")
    research.setdefault("expiredNoQuote", 0)
    return research


def _net_pct(side, start, finish):
    direction = 1 if side == "BUY" else -1
    return 100 * direction * ((finish / start) - 1) - COST_PCT


def settle(state, latest, t):
    """Check previously recorded signals at a strictly later observed price."""
    research = migrate(state)
    pending = []
    for sample in research["pending"]:
        if not isinstance(sample, dict):
            continue
        placed = _date(sample.get("at"))
        start = sample.get("entryPriceTry")
        symbol = sample.get("symbol")
        side = sample.get("action")
        if (placed is None or placed > t or
                not isinstance(start, (int, float)) or
                not math.isfinite(start) or start <= 0 or
                not isinstance(symbol, str) or
                side not in ("BUY", "SHORT")):
            research["expiredNoQuote"] += 1
            continue
        age = (t - placed).total_seconds()
        if age < HORIZON_SECONDS:
            pending.append(sample)
            continue
        current = _price(latest, symbol)
        if current is None or age > HORIZON_SECONDS + GRACE_SECONDS:
            if age <= HORIZON_SECONDS + GRACE_SECONDS:
                pending.append(sample)
            else:
                research["expiredNoQuote"] += 1
            continue
        result = {**sample, "measuredAt": _stamp(t),
                  "exitPriceTry": current,
                  "horizonActualMinutes": round(age / 60, 2),
                  "netReturnPct": round(_net_pct(side, start, current), 5),
                  "assumedRoundTripCostPct": COST_PCT}
        research["completed"].append(result)
    research["pending"] = pending[-MAX_PENDING:]
    research["completed"] = research["completed"][-MAX_COMPLETED:]
    return summary(state)


def record(state, latest, plan, t):
    """Record max 3 verified engine candidates. Never make an order here."""
    research = migrate(state)
    if not isinstance(plan, dict):
        return 0
    new_count = 0
    for candidate in plan.get("candidates", [])[:8]:
        if not isinstance(candidate, dict):
            continue
        symbol = candidate.get("symbol")
        side = candidate.get("action")
        price = _price(latest, symbol)
        if price is None or side not in ("BUY", "SHORT"):
            continue
        # One observation per coin+direction per horizon; avoid autocorrelated
        # duplicates when the scheduler checks every two minutes.
        all_records = research["pending"] + research["completed"]
        same = [row for row in all_records
                if row.get("symbol") == symbol and row.get("action") == side]
        recent = _date(same[-1].get("at")) if same else None
        if recent is not None and (t - recent).total_seconds() < PER_SYMBOL_COOLDOWN_SECONDS:
            continue
        research["pending"].append({
            "at": _stamp(t), "symbol": symbol, "action": side,
            "entryPriceTry": price,
            "regime": plan.get("marketRegime", "UNKNOWN"),
            "setup": candidate.get("setupTag", "hourly"),
            "candidateScore": candidate.get("score"),
        })
        new_count += 1
        if new_count >= MAX_NEW_PER_CYCLE:
            break
    research["pending"] = research["pending"][-MAX_PENDING:]
    return new_count


def summary(state):
    research = migrate(state)
    rows = [v for v in research["completed"]
            if isinstance(v, dict)
            and isinstance(v.get("netReturnPct"), (int, float))
            and math.isfinite(v["netReturnPct"])]
    def part(xs):
        vals = [v["netReturnPct"] for v in xs]
        return {
            "samples": len(vals),
            "avgNetPct": round(statistics.mean(vals), 4) if vals else None,
            "winRatePct": round(100 * sum(x > 0 for x in vals) / len(vals), 2)
            if vals else None,
            "medianNetPct": round(statistics.median(vals), 4) if vals else None,
        }
    out = part(rows)
    out.update({
        "pending": len(research["pending"]),
        "expiredNoQuote": research["expiredNoQuote"],
        "costAssumptionPct": COST_PCT,
        "horizonMinutes": HORIZON_SECONDS // 60,
        "status": "EVIDENCE_AVAILABLE" if len(rows) >= MIN_SAMPLES_FOR_LEARNING
                  else "COLLECTING",
        "spot": part([x for x in rows if x.get("action") == "BUY"]),
        "short": part([x for x in rows if x.get("action") == "SHORT"]),
    })
    return out


def evidence_bias(state, side, regime):
    """Bounded candidate tie-break only after 30 realized future observations.

    It is NOT a fit-for-trading signal or permission to override safety limits.
    The sample contains correlated candidate selections; expect uncertainty.
    """
    if side not in ("BUY", "SHORT"):
        return 0.0
    research = migrate(state)
    rows = [row for row in research["completed"]
            if row.get("action") == side and row.get("regime") == regime
            and isinstance(row.get("netReturnPct"), (int, float))
            and math.isfinite(row["netReturnPct"])]
    n = len(rows)
    if n < MIN_SAMPLES_FOR_LEARNING:
        return 0.0
    mean = statistics.mean(r["netReturnPct"] for r in rows)
    return round(max(-.04, min(.04, (mean / 100) * 3 * (n / (n + 60)))), 4)
