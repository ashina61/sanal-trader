"""Forward-validated, autonomous entry for the SAME virtual wallet.

The fixed net2_stop1 model must demonstrate its own forward outcomes, not
borrow the losing legacy momentum model's evidence. This is provisional
paper-only authorization, not a statistically proven trading advantage.
"""
import datetime as dt
import math
import statistics

from backend.strategy_lab import LANES, classify, entry_veto, valid

PREFIX = "adaptive:"
MODEL = "net2_stop1"
TARGET_NET_PCT = 2.0
STOP_NET_PCT = 1.0
MAX_FRICTION_PCT = .30


def parse_time(value):
    try:
        t = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return t if t.tzinfo else None
    except (TypeError, ValueError, AttributeError):
        return None


def lane_evidence(state, lane, now):
    book = state.get("strategyLabV1", {}).get(lane, {})
    rows = [r for r in book.get("observedExitPathsV1", [])
            if r.get("model") == MODEL and valid(r.get("netPct"))
            and (when := parse_time(r.get("at"))) is not None and when <= now]
    rows = sorted(rows, key=lambda r: parse_time(r["at"]))[-48:]
    values = [r["netPct"] for r in rows]
    tail = values[-12:]
    gains = sum(x for x in values if x > 0)
    losses = -sum(x for x in values if x < 0)
    pf = gains/losses if losses else None
    mean = statistics.mean(values) if values else None
    recent = statistics.mean(tail) if tail else None
    hours = len({parse_time(r["at"]).replace(minute=0, second=0, microsecond=0)
                 for r in rows})
    symbols = len({r["symbol"] for r in rows})
    age = (now-parse_time(rows[-1]["at"])).total_seconds() if rows else None
    # Require multiple chronological windows, not just correlated coins
    # during one market move; this is still not an independent holdout.
    ready = (len(values) >= 24 and hours >= 8 and symbols >= 6
             and age is not None and 0 <= age <= 10800
             and mean >= .25 and recent >= .20
             and sum(x > 0 for x in values)/len(values) >= .45
             and (pf is None or pf >= 1.30))
    action = "SHORT" if lane in ("breakdown_retest", "relative_fade") else "BUY"
    key = ("short:" if action == "SHORT" else "spot:") + PREFIX + lane
    closed = state.get("signalStats", {}).get(key, {})
    # Realized paper loss overrides the forward proxy.
    if closed.get("closed", 0) >= 3 and closed.get("netTry", 0) < 0:
        ready = False
    # Limited paper exploration, explicitly NOT a validated trading edge.
    pilot = (not ready and len(values) >= 3 and symbols >= 3
             and age is not None and 0 <= age <= 10800
             and mean >= .20 and recent >= .20
             and sum(x > 0 for x in values)/len(values) >= .60
             and (pf is None or pf >= 1.5)
             and closed.get("netTry", 0) >= 0)
    return {"ready": ready, "pilotReady": pilot, "samples": len(values), "distinctHours": hours,
            "distinctSymbols": symbols, "avgNetPct": round(mean, 4) if mean is not None else None,
            "recentNetPct": round(recent, 4) if recent is not None else None,
            "profitFactor": round(pf, 4) if pf is not None else None,
            "action": action, "model": MODEL, "targetNetPct": TARGET_NET_PCT,
            "stopNetPct": STOP_NET_PCT}


def readiness(state, now):
    return {lane: lane_evidence(state, lane, now) for lane in LANES}


def candidates(state, latest, now, equity, exposure):
    """Separate validated strategy lane; old policy gates are not modified."""
    if not state.get("ohlcvReaderActive"):
        return []
    signals = state.get("openSignals", {})
    if any(str(x.get("setup", "")).startswith(PREFIX)
           for x in signals.values() if isinstance(x, dict)):
        return []
    if not all(valid(x) for x in (equity, exposure, state.get("cashTry"))):
        return []
    # Model risk ~0.25% of equity at the 1% net stop plus gap buffer;
    # one position at a time, at most 18% notional, no leverage increase.
    amount = math.floor(max(0, min(equity*.18, equity*.0025/.014,
        (state["cashTry"]-equity*.20)/1.001, equity*.78-exposure))*100)/100
    if amount < 5:
        return []
    evidence = readiness(state, now)
    if not any(proof["ready"] or proof["pilotReady"] for proof in evidence.values()):
        return []
    found = []
    for symbol, quote in latest.items():
        if quote.get("entryEligible") is False or symbol in state.get("holdings", {}) or symbol in state.get("shorts", {}):
            continue
        for lane, action, rank in classify(state, symbol, quote.get("priceTry"), now):
            proof = evidence[lane]
            if not (proof["ready"] or proof["pilotReady"]) or action != proof["action"]:
                continue
            pilot = not proof["ready"]
            if pilot:
                recent_pilot = []
                for trade in state.get("trades", []):
                    when = parse_time(trade.get("at"))
                    if (when and 0 <= (now-when).total_seconds() < 86400
                            and trade.get("side") in ("sell", "cover")
                            and str(trade.get("reason", "")).startswith("Adaptif deneme ")):
                        recent_pilot.append(trade)
                loss = sum(max(0, -r.get("realizedPnlTry", 0)) for r in recent_pilot)
                if len(recent_pilot) >= 6 or loss >= 2:
                    continue
                pilot_stats = state.get("signalStats", {}).get(
                    ("short:" if action == "SHORT" else "spot:") + PREFIX + "pilot:" + lane, {})
                if pilot_stats.get("closed", 0) >= 3 and pilot_stats.get("netTry", 0) < 0:
                    continue
            ticket = min(amount, math.floor(equity*.12*100)/100) if pilot else amount
            if ticket < 5:
                continue
            side = "short" if action == "SHORT" else "buy"
            if entry_veto(state, symbol, side, now):
                continue
            found.append({"symbol": symbol, "action": action, "side": side,
                "setupTag": PREFIX+("pilot:" if pilot else "")+lane, "amountTry": ticket,
                "score": proof["avgNetPct"], "volumeRank": rank,
                "evidence": {**proof, "exploratoryPaperOnly": pilot}, "targetNetTry": round(ticket*.02, 2),
                "modelStopNetTry": round(ticket*.01, 2)})
    return sorted(found, key=lambda x: (-x["score"], -x["volumeRank"], x["symbol"]))


def exit_reason(state, symbol, side, price, now):
    """Match the forward target/stop model with actual paper entry and fees.

    Use only observed current marks. Exit before any normal strategy/AI gate.
    """
    info = state.get("openSignals", {}).get(symbol, {})
    if not str(info.get("setup", "")).startswith(PREFIX) or info.get("side") != side:
        return None
    amount = info.get("amountTry")
    if not valid(amount) or amount <= 0 or not valid(price) or price <= 0:
        return None
    pos = state.get("holdings" if side == "buy" else "shorts", {}).get(symbol, {})
    qty = pos.get("quantity")
    if not valid(qty) or qty <= 0:
        return None
    gross = qty*price
    if side == "buy":
        net = gross*.999-pos["costTry"]
    else:
        net = pos["marginTry"]+(pos["entryPriceTry"]-price)*qty-gross*.001-pos["marginTry"]-pos["entryFeeTry"]
    # Additional 0.1% conservative reserve mirrors research friction.
    pct = 100*net/amount-.1
    opened = parse_time(info.get("openedAt"))
    label = "Adaptif deneme " if info["setup"].startswith(PREFIX+"pilot:") else "Adaptif "
    if pct <= -STOP_NET_PCT:
        return label + "zarar kes: gözlenen net %+.2f" % pct
    if pct >= TARGET_NET_PCT:
        return label + "kâr al: gözlenen net %+.2f" % pct
    if opened and (now-opened).total_seconds() >= 3600:
        return label + "süre çıkışı: 60dk, gözlenen net %+.2f" % pct
    return None
