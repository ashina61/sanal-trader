"""Read-only diagnostics from the SAME single paper wallet's closed trades.

Realized PnL already includes the exchange-paper opening and closing fees.
Never subtract them twice. No model fit or automatic parameter changes.
"""
import math
import statistics


def _valid(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value))


def _summary(rows):
    net = [float(r["realizedPnlTry"]) for r in rows]
    wins = [v for v in net if v > 0]
    losses = [v for v in net if v < 0]
    return {
        "closed": len(net),
        "wins": len(wins),
        "losses": len(losses),
        "winRatePct": round(100 * len(wins) / len(net), 2) if net else None,
        "netRealizedTry": round(sum(net), 4),
        "avgNetPerCloseTry": round(statistics.mean(net), 4) if net else None,
        "medianNetTry": round(statistics.median(net), 4) if net else None,
        "profitFactor": round(sum(wins) / abs(sum(losses)), 3)
            if losses else None,
        "biggestLossTry": round(min(net), 4) if net else None,
    }


def summarize(state):
    """Compute net closed-trade cohorts on the bounded stored trade tape."""
    tape = state.get("trades") or []
    trades = [v for v in tape
              if isinstance(v, dict) and v.get("side") in ("sell", "cover")
              and _valid(v.get("realizedPnlTry"))]
    # The tape is newest-first, but this is not a permanent full trade ledger.
    last = trades[:10]
    recent_loss_streak = 0
    for item in trades:
        if item["realizedPnlTry"] >= 0:
            break
        recent_loss_streak += 1
    spot = [r for r in trades if r["side"] == "sell"]
    short = [r for r in trades if r["side"] == "cover"]
    by_exit = {}
    for trade in trades:
        reason = str(trade.get("reason", ""))
        category = (
            "STOP" if "zarar kes" in reason.lower() else
            "TAKE_PROFIT" if "kâr al:" in reason.lower() else
            "TRAILING" if "kâr koru" in reason.lower()
                  or "zirve" in reason.lower() or "dipten" in reason.lower() else
            "ROTATION" if "Portföy rotasyonu" in reason else
            "OTHER"
        )
        by_exit.setdefault(category, []).append(trade)
    all_stats = _summary(trades)
    recent_stats = _summary(last)
    status = ("INSUFFICIENT_SAMPLE" if len(last) < 8 else
              "RECENT_NEGATIVE" if recent_stats["netRealizedTry"] < 0 else
              "OBSERVING")
    fees = state.get("paidFeesTry")
    return {
        "status": status,
        "source": "Single wallet closed paper trades, newest 100 records max",
        "historyBounded": True,
        "cumulativePaidFeesTry": round(float(fees), 4)
            if _valid(fees) and fees >= 0 else None,
        "feesAlreadyIncludedInRealized": True,
        "closed": all_stats, "recent10": recent_stats,
        "spot": _summary(spot), "short": _summary(short),
        "byExit": {k: _summary(v) for k, v in sorted(by_exit.items())},
        "recentLossStreak": recent_loss_streak,
        "requiresMoreEvidence": len(last) < 8,
        "autonomousTradeAuthorization": False,
        "note": "Geçmiş gözlemdir; istatistiksel avantaj veya gelecekte kâr kanıtı değil.",
    }
