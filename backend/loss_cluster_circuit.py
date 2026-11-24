"""Realized stop-loss cluster guard for the one existing paper wallet.

The guard only PAUSES new BUY/SHORT entry attempts for a finite period
after *two distinct coins* suffer observed stop losses close in time. It
never closes positions, changes stored cash, forbids SELL/COVER or blocks
research-only signal collection.

No exchange order, guaranteed loss bound, profit forecast, or stop fill.
"""
import datetime as dt
import math

UTC = dt.timezone.utc
CLUSTER_WINDOW_MINUTES = 90
ENTRY_PAUSE_AFTER_SECOND_STOP_MINUTES = 120
MIN_LOSS_FRAC_OF_INITIAL = .003


def _moment(raw):
    if not isinstance(raw, str):
        return None
    try:
        value = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return value.astimezone(UTC) if value.tzinfo else None
    except (ValueError, OverflowError):
        return None


def evaluate(state, now):
    """Find the most recent observed loss cluster; no mutable state."""
    base = {
        "status": "MONITORING",
        "blocked": False,
        "remainingMinutes": 0,
        "lastStopAt": None,
        "stopsInCluster": 0,
        "clusterNetTry": None,
        "windowMinutes": CLUSTER_WINDOW_MINUTES,
        "pauseMinutes": ENTRY_PAUSE_AFTER_SECOND_STOP_MINUTES,
        "protectiveExitsUnaffected": True,
        "researchContinues": True,
        "reason": "Gerçekleşmiş seri zarar kes nedeniyle giriş freni yok",
    }
    if not isinstance(state, dict) or not isinstance(now, dt.datetime) or now.tzinfo is None:
        return {**base, "status": "UNKNOWN", "reason": "Geçerli zaman veya kasa yok"}
    initial = state.get("initialCashTry")
    if (not isinstance(initial, (int, float))
            or isinstance(initial, bool) or not math.isfinite(initial) or initial <= 0):
        return {**base, "status": "UNKNOWN", "reason": "İlk kasa tutarı geçersiz"}
    recorded = []
    for row in state.get("trades", []):
        if not isinstance(row, dict) or row.get("side") not in ("sell", "cover"):
            continue
        pnl = row.get("realizedPnlTry")
        reason = row.get("reason")
        symbol = row.get("symbol")
        at = _moment(row.get("at"))
        if (not isinstance(pnl, (int, float)) or isinstance(pnl, bool)
                or not math.isfinite(pnl) or pnl >= 0
                or not isinstance(reason, str)
                or "zarar kes" not in reason.lower()
                or not isinstance(symbol, str) or not symbol
                or at is None or at > now):
            continue
        recorded.append((at, symbol, float(pnl)))
    recorded.sort()
    threshold = -initial * MIN_LOSS_FRAC_OF_INITIAL
    valid_pair = None
    now_utc = now.astimezone(UTC)
    for i, (when, symbol, pnl) in enumerate(recorded):
        if not 0 <= (now_utc - when).total_seconds() < ENTRY_PAUSE_AFTER_SECOND_STOP_MINUTES * 60:
            continue
        for prior_when, prior_sym, prior_pnl in recorded[:i]:
            delta = (when - prior_when).total_seconds()
            if (prior_sym != symbol
                    and 0 <= delta <= CLUSTER_WINDOW_MINUTES * 60
                    and prior_pnl + pnl <= threshold):
                valid_pair = (when, (prior_sym, symbol), prior_pnl + pnl)
    if valid_pair is None:
        return base
    at, symbols, loss = valid_pair
    remaining = max(0, ENTRY_PAUSE_AFTER_SECOND_STOP_MINUTES
                    - (now_utc - at).total_seconds() / 60)
    return {**base, "status": "RECENT_STOP_CLUSTER", "blocked": True,
            "remainingMinutes": round(remaining, 1),
            "lastStopAt": at.isoformat(timespec="seconds").replace("+00:00", "Z"),
            "stopsInCluster": 2, "symbols": list(symbols),
            "clusterNetTry": round(loss, 4),
            "reason": ("İki farklı coinde yakın zamanlı zarar kes gözlendi; "
                       "yeni sanal girişler geçici durduruldu, koruyucu "
                       "satışlar ve araştırma devam ediyor.")} 
