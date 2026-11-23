"""Six-stage *deterministic* preflight for a single server-side paper wallet.

PULSE reads a public order-book snapshot. IMPACT measures executable depth,
not future returns. EDGE measures friction only: a positive statistical
expected return is NOT claimed without out-of-sample calibration.
SIZE rechecks an already risk-approved candidate. ENTRY computes a *paper*
weighted execution mark, never submits an order. EXIT is handled by the
existing protective rules before any preflight.
"""
import math


def _finite(value):
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
        return number if math.isfinite(number) and number > 0 else None
    except (TypeError, ValueError, OverflowError):
        return None


def _levels(raw, reverse):
    if not isinstance(raw, list) or not raw:
        return None
    cleaned = []
    for row in raw[:20]:
        if not isinstance(row, (list, tuple)) or len(row) < 2:
            return None
        price, qty = _finite(row[0]), _finite(row[1])
        if price is None or qty is None:
            return None
        cleaned.append((price, qty))
    prices = [entry[0] for entry in cleaned]
    if prices != sorted(prices, reverse=reverse):
        return None
    return cleaned


def idle_trace(plan):
    action = plan.get("action", "WAIT")
    exit_active = action in ("SELL", "COVER")
    note = ("Koruyucu çıkış önce değerlendirilir; defter yeni giriş için kullanılır"
            if exit_active else "Doğrulanmış yeni giriş adayı yok; defter sorgulanmadı")
    return {
        "status": "EXIT_PRIORITY" if exit_active else "IDLE",
        "source": "Binance public depth · only when an entry is proposed",
        "symbol": plan.get("symbol"),
        "bookObserved": False, "forecastCalibrated": False,
        "stages": [
            {"name": "PULSE", "status": "SKIPPED", "detail": note},
            {"name": "IMPACT", "status": "SKIPPED", "detail": "Giriş yok"},
            {"name": "EDGE", "status": "SKIPPED", "detail": "İstatistiksel getiri tahmini yapılmıyor"},
            {"name": "SIZE", "status": "SKIPPED", "detail": "Var olan risk motoru korundu"},
            {"name": "ENTRY", "status": "SKIPPED", "detail": "Sanal emir yok"},
            {"name": "EXIT", "status": "ARMED", "detail": "Fiyat bazlı çıkışlar öncelikli"},
        ],
    }


def inspect_book(plan, book, quote_try, fx, *, fee=0.001):
    """Return an auditable preflight. No prices/returns invented on bad data."""
    trace = idle_trace(plan)
    trace["symbol"] = plan.get("symbol")
    trace["source"] = "Binance public REST 20-level depth snapshot"
    side = plan.get("action")
    gross = _finite(plan.get("amountTry"))
    quote = _finite(quote_try)
    rate = _finite(fx)
    if side not in ("BUY", "SHORT") or not plan.get("order"):
        return trace

    trace["status"] = "BLOCKED"
    def stage(name, status, detail):
        return {"name": name, "status": status, "detail": detail}

    stages = [
        stage("PULSE", "BLOCKED", "Doğrulanmış emir defteri yok"),
        stage("IMPACT", "SKIPPED", "Yeterli derinlik yok"),
        stage("EDGE", "SKIPPED", "Maliyet değerlendirilmedi"),
        stage("SIZE", "SKIPPED", "Risk bütçesi değiştirilmedi"),
        stage("ENTRY", "BLOCKED", "Sanal giriş engellendi"),
        stage("EXIT", "ARMED", "Açık pozisyonlar koruyucu kurallarla izlenir"),
    ]
    trace["stages"] = stages
    def block(reason):
        trace["reason"] = reason
        return trace

    if not isinstance(book, dict) or not gross or not quote or not rate:
        return block("Eksik fiyat veya emir defteri")
    bids = _levels(book.get("bids"), reverse=True)
    asks = _levels(book.get("asks"), reverse=False)
    if not bids or not asks or bids[0][0] >= asks[0][0]:
        return block("Boş, çapraz veya bozuk emir defteri")
    best_bid, best_ask = bids[0][0], asks[0][0]
    midpoint = (best_bid + best_ask) / 2
    spread_pct = (best_ask - best_bid) / midpoint * 100
    bids_usd = sum(p * q for p, q in bids[:5])
    asks_usd = sum(p * q for p, q in asks[:5])
    imbalance = ((bids_usd - asks_usd) / (bids_usd + asks_usd)
                 if bids_usd + asks_usd > 0 else 0.0)
    trace.update({
        "bookObserved": True,
        "spreadPct": round(spread_pct, 4),
        "imbalance": round(imbalance, 4),
        "bidNotionalUsdt": round(bids_usd, 2),
        "askNotionalUsdt": round(asks_usd, 2),
    })
    stages[0] = stage("PULSE", "OBSERVED",
                      f"İlk 5 kademe dengesizliği {imbalance:+.2f}; alış-satış kuyruğu")
    if spread_pct > 0.8:
        return block(f"Emir defteri makası %{spread_pct:.2f} çok geniş")
    if (side == "BUY" and imbalance < -0.70 or
            side == "SHORT" and imbalance > 0.70):
        return block("Emir defteri baskısı giriş yönünün tersinde")

    # Take the visible side of the book only. Limit the test size to depth;
    # prices are an optimistic instantaneous proxy and NOT guaranteed fills.
    levels = asks if side == "BUY" else bids
    # Use an exact quote-currency NOTIONAL budget. A fixed-base estimate at
    # the best level silently exceeds the requested money on deeper BUY fills.
    # A paper order's grossTry is always the budget, not requested base qty.
    quote_budget = gross / rate
    quote_left = quote_budget
    spent_usdt = 0.0
    filled = 0.0
    for price, quantity in levels:
        paid = min(price * quantity, quote_left)
        filled += paid / price
        spent_usdt += paid
        quote_left -= paid
        if quote_left <= max(1e-9, quote_budget * 1e-9):
            break
    if filled <= 0 or quote_left > max(1e-8, quote_budget * .001):
        return block("20 seviyede hedef miktarın tamamına yetecek hacim yok")
    avg_price = spent_usdt / filled
    mid_slip_pct = abs(avg_price - midpoint) / midpoint * 100
    # A last ticker that disagrees wildly with the same source's book mark is
    # stale or inconsistent; always reject, do not interpolate fake prices.
    ticker_usdt = quote / rate
    deviation_pct = abs(midpoint / ticker_usdt - 1) * 100
    if deviation_pct > 1:
        return block("Emir defteri ile son fiyat uyuşmuyor")
    stages[1] = stage("IMPACT", "OBSERVED",
                      f"20 kademe sanal ortalama, orta fiyattan %{mid_slip_pct:.2f} uzak")
    if mid_slip_pct > 0.8:
        return block("Derinlikte kayma eşiği aşıldı")

    # EDGE is a transaction-cost veto, NOT a winning probability or future
    # liquidation price: there is no trained alpha model yet.
    friction_pct = mid_slip_pct * 2 + 2 * fee * 100
    trace.update({
        "frictionPct": round(friction_pct, 4),
        "estimatedEntryPriceTry": round(avg_price * rate, 8),
        "forecastCalibrated": False,
    })
    stages[2] = stage("EDGE", "COST_ONLY",
                      f"Gidiş-dönüş varsayımsal maliyet >= %{friction_pct:.2f}; alpha bilinmiyor")
    if friction_pct > 1.2:
        return block("Komisyon + emir defteri kayması yüksek")
    stages[3] = stage("SIZE", "CHECKED",
                      f"Risk motorunun onayladığı {gross:.2f} TL; 20 kademede karşılığı var")
    stages[4] = stage("ENTRY", "PAPER_ESTIMATE",
                      "Gözlenen emir defterinden tahmini alış/satış ağırlıklı fiyat")
    trace["status"] = "PASSED"
    trace["reason"] = "Emir defteri maliyet ve derinlik denetimi geçti"
    return trace


def guard_plan(plan, market, latest, fx):
    """Query a book only for an already approved entry. Exits are untouched."""
    if plan.get("action") not in ("BUY", "SHORT") or not plan.get("order"):
        return plan, idle_trace(plan)
    source = getattr(market, "depth", None)
    if not callable(source):
        # Fail closed for ANY market object. Test providers must supply a
        # realistic explicit book; missing source cannot silently bypass gate.
        trace = inspect_book(
            plan, None, latest.get(plan["symbol"], {}).get("priceTry"), fx)
        trace["reason"] = "Emir defteri sağlayıcısı desteklenmiyor"
        revised = dict(plan, action="WAIT", order=None, symbol=None,
                       amountTry=None,
                       reason="Yeni sanal giriş engellendi: " + trace["reason"])
        return revised, trace
    try:
        book = source(plan["symbol"])
    except Exception as exc:
        book = None
        reason = "Emir defteri verisi alınamadı: " + type(exc).__name__
    else:
        reason = None
    observed = inspect_book(
        plan, book, latest.get(plan["symbol"], {}).get("priceTry"), fx)
    if reason:
        observed["reason"] = reason
    if observed["status"] != "PASSED":
        revised = dict(plan, action="WAIT", order=None, symbol=None,
                       amountTry=None,
                       reason="Yeni sanal giriş engellendi: " +
                              str(observed.get("reason") or "Emir defteri onayı yok"))
        return revised, observed
    revised = dict(plan, bookEntryPriceTry=observed["estimatedEntryPriceTry"])
    return revised, observed
