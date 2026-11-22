"""Isolated, 1x-only virtual SHORT trades.

This is NOT a perpetual futures engine: no funding, real borrow, order book or
real liquidation venue. Spot prices are used as a reference for simulation.
"""

import datetime as dt
import math

LEVERAGE = 1.0
FEE_RATE = .001
MIN_ORDER = 5.0


def timestamp(t):
    return t.astimezone(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def short_value(position, price):
    """Isolated collateral plus mark-to-market PnL, never below zero."""
    quantity = position["quantity"]
    return max(0.0, position["marginTry"] +
               (position["entryPriceTry"] - price) * quantity)


def exposure(state, prices):
    """Notional exposure of LONGs plus SHORTs, irrespective of net delta."""
    value = 0.0
    for symbol, pos in state.get("holdings", {}).items():
        if symbol not in prices:
            return None
        value += pos["quantity"] * prices[symbol]["priceTry"]
    for symbol, pos in state.get("shorts", {}).items():
        if symbol not in prices:
            return None
        value += pos["quantity"] * prices[symbol]["priceTry"]
    return value


def _log(state, t, message):
    state["lastDecision"] = message
    state["journal"] = ([{"at": timestamp(t), "message": message}] +
                        state.get("journal", []))[:40]


def open_short(state, t, symbol, notional, price, reason):
    """Lock notional-sized collateral and simulate selling borrowed units."""
    if not (math.isfinite(notional) and notional >= MIN_ORDER and
            math.isfinite(price) and price > 0):
        raise ValueError("Invalid virtual SHORT order")
    if symbol in state.get("holdings", {}) or symbol in state.setdefault("shorts", {}):
        raise ValueError("Cannot open opposite or duplicate position")
    collateral = notional / LEVERAGE
    opening_fee = notional * FEE_RATE
    if collateral + opening_fee > state["cashTry"] + 1e-8:
        raise ValueError("Insufficient virtual SHORT collateral")
    qty = notional / price
    state["cashTry"] -= collateral + opening_fee
    state["shorts"][symbol] = {
        "quantity": qty, "entryPriceTry": price, "marginTry": collateral,
        "entryFeeTry": opening_fee, "leverage": LEVERAGE,
        "openedAt": timestamp(t),
    }
    state["paidFeesTry"] += opening_fee
    state["todayOrders"] += 1
    state["lastOrder"][symbol] = timestamp(t)
    trade = {
        "at": timestamp(t), "symbol": symbol, "side": "short",
        "positionType": "short", "leverage": LEVERAGE,
        "grossTry": notional, "priceTry": price, "quantity": qty,
        "feeTry": opening_fee, "realizedPnlTry": 0.0,
        "reason": reason,
    }
    state["trades"] = ([trade] + state["trades"])[:100]
    _log(state, t, f"Sanal SHORT AÇ {symbol}: {notional:.2f} TL; {reason}")
    return trade


def close_short(state, t, symbol, price, reason):
    """Buy-to-cover and refund remaining simulated collateral.

    A gap can exceed a stop. In this isolated 1x model the loss never consumes
    more than allocated collateral + the opening fee.
    """
    pos = state.get("shorts", {}).get(symbol)
    if pos is None or not (math.isfinite(price) and price > 0):
        raise ValueError("Missing virtual SHORT or invalid closing price")
    qty = pos["quantity"]
    amount = qty * price
    if not math.isfinite(amount) or amount <= 0:
        raise ValueError("Invalid SHORT cover amount")
    gross_equity = short_value(pos, price)
    closing_fee = min(amount * FEE_RATE, gross_equity)
    refund = max(0.0, gross_equity - closing_fee)
    realized = refund - pos["marginTry"] - pos["entryFeeTry"]
    state["cashTry"] += refund
    state["realizedTry"] += realized
    state["paidFeesTry"] += closing_fee
    state["shorts"].pop(symbol)
    state["todayOrders"] += 1
    state["lastOrder"][symbol] = timestamp(t)
    trade = {
        "at": timestamp(t), "symbol": symbol, "side": "cover",
        "positionType": "short", "leverage": LEVERAGE,
        "grossTry": amount, "priceTry": price, "quantity": qty,
        "feeTry": closing_fee, "realizedPnlTry": realized,
        "reason": reason,
    }
    state["trades"] = ([trade] + state["trades"])[:100]
    _log(state, t, f"Sanal SHORT KAPAT {symbol}: net {realized:+.2f} TL; {reason}")
    return trade
