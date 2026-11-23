"""One paper-wallet objective: observed value after estimated closing fees.

Opening and past closing fees already live in cash/cost basis and are NOT
subtracted twice. No hypothetical slippage is charged to historical trades.
This estimate uses current observed marks, not guaranteed execution prices.
"""
import math

from backend.short_positions import FEE_RATE, short_value


def net_liquidation(state, latest):
    value = state["cashTry"]
    closing_fees = 0.0
    for book in ("holdings", "shorts"):
        for symbol, pos in state.get(book, {}).items():
            mark = latest.get(symbol, {}).get("priceTry")
            if not isinstance(mark, (int, float)) or not math.isfinite(mark) or mark <= 0:
                return None
            gross = pos["quantity"] * mark
            if book == "holdings":
                fee = gross * FEE_RATE
                value += gross - fee
            else:
                collateral = short_value(pos, mark)
                fee = min(gross * FEE_RATE, collateral)
                value += max(0.0, collateral - fee)
            closing_fees += fee
    initial = state["initialCashTry"]
    return {"metric": "estimated-net-liquidation", "netLiquidationTry": value,
            "estimatedClosingFeesTry": closing_fees,
            "netGrowthTry": value - initial,
            "netGrowthPct": (value / initial - 1) * 100 if initial > 0 else None,
            "targetTry": initial * 2, "targetReached": value >= initial * 2,
            "goal": "Masraflar sonrası tek sanal kasayı büyütmek",
            "assumption": "Gözlenen fiyat ve mevcut model kapanış komisyonu; gerçekleşme garantisi değil"}
