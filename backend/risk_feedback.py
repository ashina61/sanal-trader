"""Measured, conservative trade-management decisions.

Rules operate only on real observed prices, candle-derived momentum and
closed-paper-trade feedback. They cannot submit orders or reset the wallet.
Research samples must never be presented as guaranteed or independent PnL.
"""
import datetime as dt
import math

LOSS_REENTRY_COOLDOWN_SECONDS = 90 * 60
BASE_SHORT_MULTIPLIER = .75
WEAK_SHORT_MULTIPLIER = .50


def _finite(value):
    return isinstance(value, (float, int)) and math.isfinite(value)


def loss_reentry_cooldown(state, pair, t):
    """Prevent repetitive loss -> immediate repurchase -> another fee cycle."""
    for trade in state.get("trades", []):
        if not isinstance(trade, dict) or trade.get("symbol") != pair:
            continue
        if trade.get("side") not in ("sell", "cover"):
            continue
        pnl = trade.get("realizedPnlTry")
        if not _finite(pnl) or pnl >= 0:
            return False
        try:
            when = dt.datetime.fromisoformat(trade["at"].replace("Z", "+00:00"))
        except (KeyError, ValueError, TypeError):
            return False
        if when.tzinfo is None:
            return False
        age = (t - when).total_seconds()
        return 0 <= age < LOSS_REENTRY_COOLDOWN_SECONDS
    return False


def broad_risk_on(breadth, btc_direction):
    if btc_direction != "up" or not isinstance(breadth, dict):
        return False
    tracked = breadth.get("tracked")
    up = breadth.get("up")
    return (isinstance(tracked, int) and tracked >= 12
            and isinstance(up, int) and up / tracked >= .70)


def short_size_multiplier(state):
    """Shorts are less validated than spot: size cautiously, still testable."""
    data = state.get("forwardEvidence", {})
    observations = [
        x for x in data.get("completed", []) if isinstance(x, dict)
        and x.get("action") == "SHORT" and _finite(x.get("netReturnPct"))
    ] if isinstance(data, dict) else []
    if len(observations) >= 6 and all(
            row["netReturnPct"] <= 0 for row in observations[-6:]):
        return WEAK_SHORT_MULTIPLIER
    return BASE_SHORT_MULTIPLIER


def short_reversal_exit(age_seconds, adverse, fast, micro, breadth, regime):
    """Short is underwater and its own 15m+1m trend rebounded in a broad bull.

    Never use BTC/breadth alone: require independently observed coin follow-
    through on two time scales, >45 minutes held, and meaningful adverse move.
    """
    if (not _finite(age_seconds) or age_seconds < 45 * 60
            or not _finite(adverse) or adverse < .006
            or regime != "YÜKSELİŞ"
            or not broad_risk_on(breadth, "up")
            or not isinstance(fast, dict) or not isinstance(micro, dict)):
        return False
    return (fast.get("momentum1h", -math.inf) >= .30
            and fast.get("momentum4h", -math.inf) >= .65
            and micro.get("momentum15", -math.inf) >= .30)


def spot_trend_failure_exit(age_seconds, move, fast, micro, tech):
    """Reduce stale losing longs only after confirmed multi-timeframe reversal."""
    if (not _finite(age_seconds) or age_seconds < 2 * 60 * 60
            or not _finite(move) or not (-.045 < move <= -.007)
            or not isinstance(fast, dict)
            or not isinstance(micro, dict) or not isinstance(tech, dict)
            or tech.get("direction") != "down"
            or tech.get("score", 0) > -.50):
        return False
    return (fast.get("momentum1h", math.inf) <= -.35
            and fast.get("momentum4h", math.inf) <= -.80
            and micro.get("momentum15", math.inf) <= -.30)


def position_monitor(state, latest, t):
    """Explain CURRENT mark-to-market loss, exposure and age without trades.

    Spot net below includes the expected exit fee on the current public quote.
    Short below includes both entry and estimated exit fees, not funding.
    """
    latest_trades = {}
    for row in state.get("trades", []):
        if not isinstance(row, dict):
            continue
        pair, side = row.get("symbol"), row.get("side")
        if side != "buy" or pair in latest_trades:
            continue
        latest_trades[pair] = row.get("at")
    result = []
    for side, positions in (
            ("SPOT", state.get("holdings", {})),
            ("SHORT", state.get("shorts", {}))):
        for pair, pos in positions.items():
            value = latest.get(pair)
            if not isinstance(value, dict) or not _finite(value.get("priceTry")):
                continue
            price = value["priceTry"]
            quantity = pos.get("quantity")
            if not _finite(quantity) or quantity <= 0 or price <= 0:
                continue
            gross = quantity * price
            if side == "SPOT":
                basis = pos.get("costTry")
                if not _finite(basis) or basis <= 0:
                    continue
                projected_net = gross * .999 - basis
                start_at = (state.get("openContexts", {}).get(pair, {}).get("at")
                            or latest_trades.get(pair))
                return_pct = 100 * projected_net / basis
            else:
                basis = pos.get("marginTry")
                entry = pos.get("entryPriceTry")
                if not _finite(basis) or not _finite(entry):
                    continue
                projected_net = ((entry - price) * quantity
                                 - pos.get("entryFeeTry", 0) - gross * .001)
                start_at = pos.get("openedAt")
                return_pct = 100 * projected_net / basis if basis > 0 else 0
            try:
                start = dt.datetime.fromisoformat(
                    str(start_at).replace("Z", "+00:00"))
                age = (t - start).total_seconds() / 3600
                age = max(0, round(age, 2)) if start.tzinfo else None
            except (ValueError, TypeError):
                age = None
            result.append({
                "symbol": pair, "side": side, "ageHours": age,
                "notionalTry": round(gross, 4),
                "estimatedCloseNetTry": round(projected_net, 4),
                "estimatedClosePct": round(return_pct, 3),
            })
    result.sort(key=lambda x: (x["estimatedCloseNetTry"], x["symbol"]))
    return result[:15]
