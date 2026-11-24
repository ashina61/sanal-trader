"""Equity-risk-budget sizing of a narrowly qualified SPOT breakout paper trial.

This function cannot approve an entry: the strategy, news, market, depth,
AI and loss guards must all pass separately. It only caps the trial notional.

A price-triggered paper stop is NOT an actual resting exchange-side order.
Gaps, quote latency, spread and slippage can cause a larger loss than this
scenario. We never claim a guaranteed stop or future gain.
"""
import math

from backend.profit_protection import SPOT_HARD_STOP_PCT

# Relative to the *whole* marked paper wallet, not to its free cash.
MAX_TRIAL_NOTIONAL_PCT = .18
MAX_TOTAL_BREAKOUT_PCT = .25
RISK_BUDGET_PCT = .006  # 0.60% of entire virtual equity per new trial
ROUND_TRIP_FEES_PCT = .002
ASSUMED_EXTRA_SLIPPAGE_PCT = .001  # 5bps each side
MODEL_ADVERSE_PCT = (
    SPOT_HARD_STOP_PCT + ROUND_TRIP_FEES_PCT
    + ASSUMED_EXTRA_SLIPPAGE_PCT
)


def _finite(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value))


def size_trial(state, latest, *, equity, exposure, volatility,
               cash_reserve_pct, exposure_ceiling_pct, entry_fee=.001):
    """Return an amount and transparent caps without writing to the wallet."""
    def block(reason):
        return {
            "mode": "QUALIFIED_SPOT_BREAKOUT_RISK_BUDGET",
            "approved": False, "amountTry": 0.0,
            "reason": reason,
            "assumedGrossStopPct": round(100*SPOT_HARD_STOP_PCT, 3),
            "riskBudgetTry": 0.0, "estimatedLossAtStopTry": 0.0,
            "scenarioNotGuaranteed": True,
        }
    numbers = [equity, exposure, volatility, cash_reserve_pct,
               exposure_ceiling_pct, entry_fee]
    if any(not _finite(v) for v in numbers):
        return block("Geçersiz bütçe veya fiyat verisi")
    if (equity <= 0 or exposure < 0 or volatility < 0
            or not 0 <= cash_reserve_pct <= 1
            or not 0 < exposure_ceiling_pct <= 1
            or not 0 <= entry_fee < 1
            or not isinstance(state, dict) or not isinstance(latest, dict)):
        return block("Risk parametresi geçersiz")
    cash = state.get("cashTry")
    if not _finite(cash) or cash < 0:
        return block("Nakit verisi doğrulanamadı")

    total_breakout_notional = 0.0
    for symbol, item in state.get("openSignals", {}).items():
        if (not isinstance(item, dict) or item.get("side") != "buy"
                or item.get("setup") != "breakout"
                or symbol not in state.get("holdings", {})):
            continue
        held = state["holdings"][symbol]
        mark = latest.get(symbol, {}).get("priceTry")
        quantity = held.get("quantity") if isinstance(held, dict) else None
        if not _finite(mark) or mark <= 0 or not _finite(quantity) or quantity <= 0:
            return block("Açık kırılım pozisyonunun fiyatı eksik")
        total_breakout_notional += quantity * mark

    budget_try = equity * RISK_BUDGET_PCT
    risk_capped = budget_try / MODEL_ADVERSE_PCT
    volume_scale = .65 if volatility > 6 else 1.0  # normal strategy rule
    # Preserve both existing reserve and total exposure caps, even if the
    # high-quality breakout trial has a larger single-ticket budget.
    limits = {
        "perPosition": equity * MAX_TRIAL_NOTIONAL_PCT,
        "riskBudget": risk_capped,
        "breakoutGroup": equity * MAX_TOTAL_BREAKOUT_PCT
            - total_breakout_notional,
        "cashReserve": (cash - equity * cash_reserve_pct) / (1 + entry_fee),
        "totalExposure": equity * exposure_ceiling_pct - exposure,
        "availableCash": cash / (1 + entry_fee),
    }
    maximum = max(0.0, min(limits.values()))
    amount = math.floor(maximum * volume_scale * 100) / 100
    return {
        "mode": "QUALIFIED_SPOT_BREAKOUT_RISK_BUDGET",
        "approved": amount >= 5.0, "amountTry": amount,
        "riskBudgetTry": round(budget_try, 4),
        "estimatedLossAtStopTry": round(amount*MODEL_ADVERSE_PCT, 4),
        "assumedGrossStopPct": round(100*SPOT_HARD_STOP_PCT, 3),
        "assumedTotalAdversePct": round(100*MODEL_ADVERSE_PCT, 3),
        "breakoutAlreadyOpenTry": round(total_breakout_notional, 4),
        "volumeScale": volume_scale,
        "maxPerPositionPct": 100*MAX_TRIAL_NOTIONAL_PCT,
        "maxGroupPct": 100*MAX_TOTAL_BREAKOUT_PCT,
        "limitsTry": {k: round(max(0, v), 4) for k, v in limits.items()},
        "scenarioNotGuaranteed": True,
        "reason": (
            "Tamamen sanal: hesap özsermayesinin %0,60 model risk bütçesi "
            "ve %18 azami giriş. Gecikme ve gap daha büyük zarar üretebilir."
        ),
    }
