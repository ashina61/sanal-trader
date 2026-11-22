#!/usr/bin/env python3
"""Free scheduled paper trading. Public market-data GET calls only; no exchange orders."""
import argparse
import datetime as dt
import json
import math
import os
import re
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from backend.ai_brain import apply_ai_brain

from backend.short_positions import (short_value, exposure, open_short,
    close_short, learn_closed_direction, direction_edge)

UTC = dt.timezone.utc
INITIAL = 650.0
FEE = .001
MIN_ORDER = 5.0
CORE = ("BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "BNBUSDT", "DOGEUSDT")
STABLE = {"USDT","USDC","FDUSD","TUSD","USDD","DAI","USDP","BUSD","EUR","TRY","BRL","GBP","AUD","PAXG","XAUT","EURI","AEUR","USTC","LUNA","WBTC","WETH","BFUSD","RLUSD","PYUSD","USD1","USDG","USDJ"}
API = "https://data-api.binance.vision"

def now_utc():
    return dt.datetime.now(UTC)

def stamp(t):
    return t.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")

def as_date(s):
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None
    except (ValueError, AttributeError):
        return None

def numeric(value):
    try:
        n = float(value)
        return n if math.isfinite(n) else None
    except (TypeError, ValueError, OverflowError):
        return None

def fresh_state():
    return dict(schema=1, enabled=True, mode="server-paper", cashTry=INITIAL,
                initialCashTry=INITIAL, equityTry=INITIAL, peakEquityTry=INITIAL,
                holdings={}, shorts={}, directionStats={}, trades=[], journal=[], day="", todayOrders=0,
                lastOrder={}, realizedTry=0.0, paidFeesTry=0.0, histories={},
                lastSuccessAt=None, lastRunAt=None, lastError=None, marksTry={},
                source="Binance public spot REST", lastDecision="İlk kontrol bekleniyor",
                tracked=0, cycles=0, decisionPlan=None,
                aiBrain={"status": "NOT_CONFIGURED", "provider": "Groq"},
                lastTriggerEvent=None, lastTriggerAt=None,
                lastScheduledTriggerAt=None, peakMarksTry={},
                troughMarksTry={}, equityHistory=[], performance={})

def load(path):
    if not path.exists():
        return fresh_state()
    obj = json.loads(path.read_text(encoding="utf-8"))
    if (obj.get("schema") != 1 or not isinstance(obj.get("holdings"), dict)
            or not isinstance(obj.get("trades"), list)
            or numeric(obj.get("cashTry")) is None
            or obj["cashTry"] < -1e-6):
        raise ValueError("Invalid persistent wallet; refusing reset")
    # Preserve pre-0.9.0 wallets; never reset real simulated positions.
    obj.setdefault("shorts", {})
    obj.setdefault("directionStats", {})
    obj.setdefault("lastTriggerEvent", None)
    obj.setdefault("lastTriggerAt", None)
    obj.setdefault("lastScheduledTriggerAt", None)
    obj.setdefault("peakMarksTry", {})
    obj.setdefault("troughMarksTry", {})
    obj.setdefault("equityHistory", [])
    obj.setdefault("performance", {})
    if not isinstance(obj["peakMarksTry"], dict) or not isinstance(obj["troughMarksTry"], dict) or not isinstance(obj["equityHistory"], list):
        raise ValueError("Invalid virtual performance history")
    if not isinstance(obj["directionStats"], dict):
        raise ValueError("Invalid virtual outcome learning state")
    if not isinstance(obj["shorts"], dict):
        raise ValueError("Corrupt virtual SHORT book")
    for symbol, position in obj["shorts"].items():
        if (not isinstance(position, dict) or
                any(numeric(position.get(key)) is None or
                    numeric(position.get(key)) <= 0
                    for key in ("quantity", "marginTry", "entryPriceTry"))):
            raise ValueError(f"Invalid virtual SHORT position: {symbol}")
    return obj

def save(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2,
                         allow_nan=False) + "\n"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(payload, encoding="utf-8")
    os.replace(tmp, path)

def log(state, t, message):
    state["lastDecision"] = message
    state["journal"] = ([{"at": stamp(t), "message": message}] +
                        state.get("journal", []))[:40]

def eligible(pair):
    if not pair.endswith("USDT"):
        return False
    base = pair[:-4]
    if base in STABLE or not re.fullmatch(r"[A-Z0-9]{2,12}", base):
        return False
    return not any(base.endswith(s) for s in ("UP", "DOWN", "BULL", "BEAR", "3L", "3S", "5L", "5S"))

class Market:
    def __init__(self, url=API):
        self.url = url

    def request(self, route, params=None):
        uri = self.url + route
        if params:
            uri += "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(uri, headers={
            "Accept": "application/json", "User-Agent": "SanalTraderPaperTest/1.0"})
        for i in range(3):
            try:
                with urllib.request.urlopen(req, timeout=12) as response:
                    if response.status != 200:
                        raise ValueError("Market HTTP " + str(response.status))
                    body = response.read(3_000_001)
                    if len(body) > 3_000_000:
                        raise ValueError("Oversized market data")
                    return json.loads(body)
            except (urllib.error.URLError, ValueError, TimeoutError,
                    json.JSONDecodeError) as exc:
                if i == 2:
                    raise RuntimeError("Public data unavailable: " + str(exc)) from exc
                time.sleep(i + 1)

    def tickers(self):
        return self.request("/api/v3/ticker/24hr")

    def candles(self, symbol):
        return self.request("/api/v3/klines",
                            {"symbol": symbol, "interval": "1h", "limit": 168})

def quotes(raw, t):
    if not isinstance(raw, list):
        raise ValueError("Malformed ticker list")
    result = {}
    for item in raw:
        if not isinstance(item, dict):
            continue
        sym = item.get("symbol", "")
        price = numeric(item.get("lastPrice"))
        open_price = numeric(item.get("openPrice"))
        volume = numeric(item.get("quoteVolume"))
        close_time = numeric(item.get("closeTime"))
        if not sym or price is None or price <= 0 or volume is None or volume < 0:
            continue
        if close_time is None or abs(t.timestamp() - close_time / 1000) > 600:
            continue
        result[sym] = {
            "symbol": sym, "usdt": price, "volume": volume,
            "change": (price / open_price - 1) * 100
                        if open_price and open_price > 0 else 0.0,
        }
    fx = result.get("USDTTRY")
    if not fx or not (1 < fx["usdt"] < 1000):
        raise ValueError("Missing fresh USDT/TRY market exchange rate")
    return result, fx["usdt"]

def closes(data, t, fx):
    if not isinstance(data, list):
        return []
    points = []
    for row in data:
        if not isinstance(row, list) or len(row) < 7:
            continue
        end = numeric(row[6])
        close = numeric(row[4])
        if end is None or close is None or close <= 0 or end / 1000 > t.timestamp():
            continue
        points.append((end, close * fx))
    points = sorted(dict(points).items())
    return [float(p) for _, p in points][-168:]

def ema(series, period):
    v = series[0]
    a = 2 / (period + 1)
    for p in series[1:]:
        v += (p - v) * a
    return v

def indicators(series):
    if len(series) < 60 or not all(numeric(p) and p > 0 for p in series):
        return None
    p = series[-1]
    fast, slow = ema(series, 20), ema(series, 50)
    direction = "up" if p >= fast and fast > slow * 1.001 else (
        "down" if p < fast and fast < slow * .999 else "sideways")
    r = [math.log(series[i] / series[i-1]) for i in range(len(series)-24, len(series))]
    mean = sum(r) / len(r)
    vol = math.sqrt(sum((x-mean)**2 for x in r) / len(r)) * math.sqrt(24) * 100
    momentum6 = (p / series[-7] - 1) * 100
    momentum24 = (p / series[-25] - 1) * 100
    score = (.35 if direction == "up" else -.35 if direction == "down" else 0.0)
    score += .30 if momentum6 > .5 else -.30 if momentum6 < -.5 else 0
    score += .25 if momentum24 > 1 else -.25 if momentum24 < -1 else 0
    support, resistance = min(series[-49:-1]), max(series[-49:-1])
    if p > resistance * 1.002:
        score += .10
    if p < support * .998:
        score -= .10
    return {"direction": direction, "score": max(-1, min(1, score)),
            "volatility": vol, "momentum6": momentum6}

def equity(state, latest):
    total = state["cashTry"]
    for symbol, pos in state["holdings"].items():
        data = latest.get(symbol)
        if data is None:
            return None
        total += pos["quantity"] * data["priceTry"]
    for symbol, pos in state.get("shorts", {}).items():
        data = latest.get(symbol)
        if data is None:
            return None
        total += short_value(pos, data["priceTry"])
    return total

def execute(state, t, symbol, side, amount, price, reason):
    if not (amount > 0 and math.isfinite(amount) and
            price > 0 and math.isfinite(price)):
        raise ValueError("Bad virtual order")
    if side == "buy" and amount < MIN_ORDER:
        raise ValueError("Buy below virtual minimum")
    holdings = state["holdings"]
    fee = amount * FEE
    quantity = amount / price
    realized = 0.0
    if side == "buy":
        if symbol in state.get("shorts", {}):
            raise ValueError("Close virtual SHORT before opening LONG")
        charged = amount + fee
        if charged > state["cashTry"] + 1e-6:
            raise ValueError("Insufficient paper cash")
        old = holdings.get(symbol, {"quantity": 0.0, "costTry": 0.0})
        holdings[symbol] = {"quantity": old["quantity"] + quantity,
                            "costTry": old["costTry"] + charged}
        state["cashTry"] -= charged
    elif side == "sell":
        old = holdings.get(symbol)
        if not old or quantity > old["quantity"] + 1e-7:
            raise ValueError("Insufficient paper position")
        quantity = min(quantity, old["quantity"])
        amount = quantity * price
        fee = amount * FEE
        original = old["costTry"] * quantity / old["quantity"]
        realized = amount - fee - original
        remain = old["quantity"] - quantity
        if remain <= 1e-10:
            holdings.pop(symbol)
        else:
            holdings[symbol] = {
                "quantity": remain, "costTry": old["costTry"] - original}
        state["cashTry"] += amount - fee
        state["realizedTry"] += realized
        learn_closed_direction(state, "long", realized, original)
    else:
        raise ValueError("Unknown virtual side")
    state["paidFeesTry"] += fee
    state["lastOrder"][symbol] = stamp(t)
    state["todayOrders"] += 1
    rec = {"at": stamp(t), "symbol": symbol, "side": side, "grossTry": amount,
           "priceTry": price, "quantity": quantity, "feeTry": fee,
           "realizedPnlTry": realized, "reason": reason}
    state["trades"] = ([rec] + state["trades"])[:100]
    log(state, t, ("Sanal AL" if side == "buy" else "Sanal SAT") +
        f" {symbol}: {amount:.2f} TL; {reason}")
    return rec

def assess_decision(state, latest, t):
    """Choose SPOT BUY, SPOT SELL, virtual SHORT, SHORT COVER or WAIT.

    Decisions use observed public market marks and existing closed hourly
    histories only. No future prices, hypothetical fills or real exchange API.
    Protective closes outrank new entries, and waiting is a valid outcome.
    """
    plan = {
        "at": stamp(t), "action": "WAIT", "symbol": None, "amountTry": None,
        "score": None, "marketRegime": "VERİ BEKLENİYOR",
        "reason": "Güncel veri bekleniyor", "reviewed": 0,
        "screened": len(latest), "rejectReasons": {},
        "candidates": [], "order": None,
    }
    def wait(reason):
        plan["reason"] = reason
        return plan
    def choose(pair, side, amount, reason, score=None):
        plan.update({
            "action": {
                "buy": "BUY", "sell": "SELL",
                "short": "SHORT", "cover": "COVER",
            }[side],
            "symbol": pair, "amountTry": round(amount, 4),
            "score": round(score, 3) if score is not None else None,
            "reason": reason, "order": (pair, side, amount, reason),
        })
        return plan

    if not state.get("enabled", False):
        return wait("Sunucu botu duraklatılmış")
    total = equity(state, latest)
    if total is None or not math.isfinite(total) or total <= 0:
        return wait("Açık pozisyonların fiyatı güvenilir şekilde değerlenemedi")

    def cooled(pair):
        last = as_date(state.get("lastOrder", {}).get(pair))
        return last is None or (t - last).total_seconds() >= 1800

    def current_tech(pair):
        record = state.get("histories", {}).get(pair, {})
        fetched = as_date(record.get("fetchedAt"))
        if fetched and (
            fetched > t or (t - fetched).total_seconds() > 7200
        ):
            return None
        history = record.get("prices", [])
        market_price = latest.get(pair, {}).get("priceTry")
        if (not isinstance(history, list) or
                len(history) < 60 or
                market_price is None or
                not math.isfinite(market_price) or market_price <= 0):
            return None
        # Append the CURRENT observed mark, not an invented future candle.
        # A >20% disagreement with the last closed bar suggests a feed,
        # conversion or extraordinary volatility problem; no new entry.
        if not math.isfinite(history[-1]) or history[-1] <= 0:
            return None
        if abs(market_price / history[-1] - 1) > .20:
            return None
        return indicators(history + [market_price])

    btc = current_tech("BTCUSDT")
    plan["marketRegime"] = (
        "YÜKSELİŞ" if btc and btc["direction"] == "up"
        else "DÜŞÜŞ" if btc and btc["direction"] == "down"
        else "YATAY" if btc else "BTC VERİSİ YOK"
    )

    exits = []
    for pair, pos in state.get("shorts", {}).items():
        quote = latest.get(pair)
        if quote is None:
            continue
        current = quote["priceTry"]
        entry = pos["entryPriceTry"]
        adverse = current / entry - 1
        technical = current_tech(pair)
        amount = pos["quantity"] * current
        if short_value(pos, current) <= pos["marginTry"] * .10:
            exits.append((130, pair, "cover", amount, "SHORT teminat koruması", technical))
        elif adverse >= .06:
            exits.append((120 + adverse, pair, "cover", amount,
                          f"SHORT zarar kes: ters hareket %{adverse*100:.1f}", technical))
        elif adverse <= -.08:
            exits.append((100 - adverse, pair, "cover", amount,
                          f"SHORT kâr al: düşüş %{abs(adverse)*100:.1f}", technical))
        elif (state.get("troughMarksTry", {}).get(pair) is not None
              and 1 - state["troughMarksTry"][pair] / entry >= .035
              and adverse <= -.008
              and current / state["troughMarksTry"][pair] - 1 >= .018):
            exits.append((91, pair, "cover", amount,
                          "SHORT takip eden kâr koruması: dipten dönüş", technical))
        elif cooled(pair) and technical and technical["score"] >= .50:
            exits.append((80 + technical["score"], pair, "cover", amount,
                          "Yükseliş trendi SHORT pozisyonla ters düştü", technical))

    for pair, pos in state["holdings"].items():
        quote = latest.get(pair)
        if quote is None or pos["quantity"] <= 0:
            continue
        amount = pos["quantity"] * quote["priceTry"]
        cost = pos["costTry"] / pos["quantity"]
        move = quote["priceTry"] / cost - 1
        technical = current_tech(pair)
        # Protective exits can close small remaining dust positions too.
        if move <= -.06:
            exits.append((120 - move, pair, "sell", amount,
                          f"Spot zarar kes: düşüş %{abs(move)*100:.1f}", technical))
        elif move >= .08:
            exits.append((100 + move, pair, "sell", amount,
                          f"Spot kâr al: yükseliş %{move*100:.1f}", technical))
        elif (state.get("peakMarksTry", {}).get(pair) is not None
              and state["peakMarksTry"][pair] / cost - 1 >= .035
              and move >= .008
              and quote["priceTry"] / state["peakMarksTry"][pair] - 1 <= -.018):
            exits.append((91, pair, "sell", amount,
                          "LONG takip eden kâr koruması: zirveden dönüş", technical))
        elif cooled(pair) and technical and technical["score"] < -.50:
            exits.append((80 - technical["score"], pair, "sell", amount,
                          "Momentum düşüşe döndü; açık LONG kapatılıyor", technical))

    if exits:
        priority, pair, side, amount, reason, technical = max(
            exits, key=lambda item: (item[0], item[3]))
        plan["reviewed"] = len(latest)
        return choose(pair, side, amount, reason,
                      technical["score"] if technical else None)

    # Controls below block NEW positions only, never protective exits.
    if state.get("todayOrders", 0) >= 8:
        return wait("Günlük 8 sanal emir sınırı; yeni pozisyon açılmadı")
    if total < state.get("peakEquityTry", total) * .88:
        return wait("Portföy gerilemesi %12'yi geçti; yeni risk durduruldu")
    used = exposure(state, latest)
    if used is None:
        return wait("Açık pozisyonlar için güvenilir piyasa değeri yok")

    # One cautious SPOT portfolio rotation per UTC day. When nearly at
    # capacity, allow selling a fading, nearly flat position ONLY when a
    # verified stronger candidate is available. No forced trade without edge.
    # Existing protective exits still take precedence above this block.
    if (used >= total * .60 and state.get("todayOrders", 0) <= 6
            and btc and btc["direction"] != "down"):
        rotated_today = any(
            str(order.get("reason", "")).startswith("Portföy rotasyonu")
            and (as_date(order.get("at")) or dt.datetime.min.replace(
                tzinfo=UTC)).date() == t.date()
            for order in state.get("trades", [])
            if isinstance(order, dict)
        )
        if not rotated_today:
            leaders = []
            for pair in latest:
                if (pair in state["holdings"] or pair in state.get("shorts", {})
                        or not cooled(pair)):
                    continue
                tech = current_tech(pair)
                if not tech or tech["volatility"] > 9:
                    continue
                if (tech["direction"] == "up" and tech["score"] >= .85
                        and tech["momentum6"] >= 1.0):
                    leaders.append((tech["score"], tech["momentum6"], pair))
            if leaders:
                best_score, _, best_pair = max(leaders)
                fading = []
                for pair, pos in state["holdings"].items():
                    quote = latest.get(pair)
                    when = as_date(state.get("lastOrder", {}).get(pair))
                    if not quote or not when or (t - when).total_seconds() < 5400:
                        continue
                    tech = current_tech(pair)
                    if tech is None:
                        continue
                    entry = pos["costTry"] / pos["quantity"]
                    pnl_ratio = quote["priceTry"] / entry - 1
                    # Avoid panic-selling meaningful losses to chase a pump.
                    if (-.0075 <= pnl_ratio <= .015 and
                            tech["score"] <= .35 and tech["momentum6"] < 0
                            and best_score - tech["score"] >= .50):
                        fading.append((tech["score"], pair, tech))
                if fading:
                    _, pair, tech = min(fading, key=lambda item: (item[0], item[1]))
                    gross = (state["holdings"][pair]["quantity"] *
                             latest[pair]["priceTry"])
                    plan["rotation"] = {
                        "exit": pair, "candidate": best_pair,
                        "reason": "Yüksek maruziyette zayıf momentum yerine güçlü aday",
                    }
                    plan["reviewed"] = len(latest)
                    return choose(
                        pair, "sell", gross,
                        f"Portföy rotasyonu: {pair} momentumu zayıfladı; "
                        f"{best_pair} için daha güçlü sinyal var. "
                        "Yeni pozisyon ancak sonraki doğrulanmış döngüde açılabilir.",
                        tech["score"])

    if used >= total * .65:
        return wait("Toplam LONG+SHORT maruziyeti %65 sınırında; "
                    "uygun güvenli rotasyon adayı yok")
    if state["cashTry"] <= total * .30:
        return wait("Minimum %30 sanal nakit rezervi korunuyor")

    candidates = []
    reasons = {}
    def rejected(label):
        reasons[label] = reasons.get(label, 0) + 1
    for pair, quote in latest.items():
        if pair in state["holdings"] or pair in state.get("shorts", {}):
            rejected("Zaten açık pozisyon")
            continue
        if not cooled(pair):
            rejected("30 dk bekleme")
            continue
        tech = current_tech(pair)
        if tech is None:
            rejected("Yetersiz / eski mum")
            continue
        if tech["volatility"] > 18:
            rejected("Aşırı oynaklık")
            continue
        plan["reviewed"] += 1
        # The observed movement must exceed round-trip 0.2% fees plus
        # a safety buffer. Trading without a signal is not learning.
        if abs(tech["momentum6"]) < .6:
            rejected("Zayıf 6s momentum")
            continue
        if pair != "BTCUSDT" and btc is None:
            rejected("BTC grafik verisi yok")
            continue
        mode = None
        if tech["direction"] == "up" and tech["score"] >= .55:
            if pair == "BTCUSDT" or btc["direction"] != "down":
                mode = "buy"
            else:
                rejected("BTC rejimi")
        elif tech["direction"] == "down" and tech["score"] <= -.70:
            if pair == "BTCUSDT" or btc["direction"] != "up":
                mode = "short"
            else:
                rejected("BTC rejimi")
        else:
            rejected("Zayıf trend/sinyal")
        if mode is None:
            continue
        upper = min(
            total * .12, state["cashTry"] / 1.001,
            (state["cashTry"] - total * .30) / 1.001,
            total * .25, total * .65 - used,
        )
        scale = (.4 if tech["volatility"] > 9 else
                 .65 if tech["volatility"] > 6 else 1.0)
        amount = math.floor(max(0.0, upper) * scale * 100) / 100
        if amount < MIN_ORDER:
            rejected("Kullanılabilir sanal tutar")
            continue
        direction = "long" if mode == "buy" else "short"
        score = ((tech["score"] if mode == "buy" else -tech["score"])
                 + direction_edge(state, direction))
        candidates.append((score, pair, mode, amount, tech))
    plan["rejectReasons"] = dict(sorted(reasons.items(),
                                     key=lambda item: (-item[1], item[0])))

    candidates.sort(key=lambda item: (-item[0], item[1]))
    plan["candidates"] = [
        {
            "symbol": pair,
            "action": "BUY" if side == "buy" else "SHORT",
            "score": round(score, 3),
            "volatilityPct": round(tech["volatility"], 2),
            "momentum6Pct": round(tech["momentum6"], 2),
        }
        for score, pair, side, _, tech in candidates[:5]
    ]
    if not candidates:
        primary = next(iter(plan["rejectReasons"].items()), None)
        detail = f" En sık neden: {primary[0]} ({primary[1]} coin)." if primary else ""
        return wait("Yeterli trend/momentum, maliyet payı ve risk koşulu oluşmadı." + detail)
    plan["aiChoices"] = [
        {"symbol": pair, "action": "BUY" if side == "buy" else "SHORT",
         "amountTry": amount, "score": round(score, 3)}
        for score, pair, side, amount, tech in candidates[:5]
    ]
    score, pair, side, amount, tech = candidates[0]
    mode = "SPOT AL / LONG" if side == "buy" else "SANAL 1x SHORT"
    return choose(
        pair, side, amount,
        f"{mode} · {plan['marketRegime']} piyasası · "
        f"sinyal {tech['score']:+.2f}, 6s momentum "
        f"%{tech['momentum6']:+.1f}, oynaklık %{tech['volatility']:.1f}",
        score=score,
    )


def pick(state, latest, t):
    """Backward compatible order planning API for existing bot tests."""
    return assess_decision(state, latest, t)["order"]


def update_price_extremes(state, latest):
    """Remember only genuinely observed marks for currently open positions."""
    peaks = state.setdefault("peakMarksTry", {})
    troughs = state.setdefault("troughMarksTry", {})
    for pair in list(peaks):
        if pair not in state["holdings"]:
            peaks.pop(pair, None)
    for pair in list(troughs):
        if pair not in state.get("shorts", {}):
            troughs.pop(pair, None)
    for pair, pos in state["holdings"].items():
        price = numeric(latest.get(pair, {}).get("priceTry"))
        if price is None or price <= 0:
            continue
        old = numeric(peaks.get(pair))
        if old is None or old <= 0:
            old = pos["costTry"] / pos["quantity"]
        peaks[pair] = max(old, price)
    for pair, pos in state.get("shorts", {}).items():
        price = numeric(latest.get(pair, {}).get("priceTry"))
        if price is None or price <= 0:
            continue
        old = numeric(troughs.get(pair))
        if old is None or old <= 0:
            old = pos["entryPriceTry"]
        troughs[pair] = min(old, price)


def record_performance(state, t):
    """Only observed simulated equity and closed-trade P&L, never forecasts."""
    current = numeric(state.get("equityTry"))
    initial = numeric(state.get("initialCashTry"))
    if current is None or initial is None or initial <= 0:
        return
    peak = max(numeric(state.get("peakEquityTry")) or current, current)
    state["peakEquityTry"] = peak
    closed = [item for item in state.get("trades", [])
              if isinstance(item, dict) and item.get("side") in ("sell", "cover")]
    wins = sum(1 for item in closed
               if (numeric(item.get("realizedPnlTry")) or 0) > 0)
    state["performance"] = {
        "netTry": round(current - initial, 4),
        "returnPct": round((current / initial - 1) * 100, 3),
        "drawdownPct": round(max(0, 1 - current / peak) * 100, 3),
        "closedTrades": len(closed), "wins": wins,
        "winRatePct": round(wins * 100 / len(closed), 1) if closed else None,
        "feesTry": round(state.get("paidFeesTry", 0.0), 4),
        "realizedTry": round(state.get("realizedTry", 0.0), 4),
        "openPositions": len(state["holdings"]) + len(state.get("shorts", {})),
    }
    points = state.setdefault("equityHistory", [])
    recent = (as_date(points[-1].get("at"))
              if points and isinstance(points[-1], dict) else None)
    if recent and (t - recent).total_seconds() < 120:
        return
    points.append({"at": stamp(t), "equityTry": round(current, 4),
                   "cashTry": round(state["cashTry"], 4)})
    state["equityHistory"] = points[-576:]


def cycle(state, market, t):
    state = json.loads(json.dumps(state))
    state["lastRunAt"] = stamp(t)
    state["cycles"] += 1
    if not state.get("enabled", False):
        state["decisionPlan"] = {
            "at": stamp(t), "action": "WAIT", "symbol": None,
            "amountTry": None, "score": None,
            "marketRegime": "DURDURULDU",
            "reason": "Bot durduruldu", "reviewed": 0, "candidates": [],
        }
        log(state, t, "Sunucu botu duraklatılmış.")
        return state
    last = as_date(state.get("lastSuccessAt"))
    if last and (t - last).total_seconds() < 150:
        # A near-duplicate push/cron event is not a new trading decision.
        # Preserve the prior decision and only record a heartbeat.
        state["journal"] = ([{"at": stamp(t), "message":
            "Tekrarlanan kontrol atlandı; önceki karar korundu."}] +
            state.get("journal", []))[:40]
        return state
    try:
        lookup, rate = quotes(market.tickers(), t)
        eligible_pairs = [v for v in lookup.values() if eligible(v["symbol"])
                          and v["volume"] >= 1_000_000]
        eligible_pairs.sort(key=lambda x: x["volume"], reverse=True)
        if not eligible_pairs:
            raise ValueError("No liquid spot quotes")
        # Scan more than the first 24 liquid symbols. Recent gainers and
        # losers provide broader LONG / SHORT opportunities; all still pass
        # volume, volatility, history, and risk filters before any paper order.
        selected_pairs = {v["symbol"] for v in eligible_pairs[:36]}
        movers_up = sorted(eligible_pairs, key=lambda x: x["change"], reverse=True)
        movers_down = sorted(eligible_pairs, key=lambda x: x["change"])
        selected_pairs.update(x["symbol"] for x in movers_up[:10])
        selected_pairs.update(x["symbol"] for x in movers_down[:10])
        selected_pairs.update(x for x in CORE if x in lookup)
        selected_pairs.update(state["holdings"].keys())
        selected_pairs.update(state.get("shorts", {}).keys())
        latest = {}
        for pair in selected_pairs:
            v = lookup.get(pair)
            if v is None:
                continue
            latest[pair] = {"symbol": pair, "priceTry": v["usdt"] * rate,
                            "volumeUsdt": v["volume"], "change24h": v["change"]}
        # Every held coin must be freshly valued, even when off the top 24.
        if equity(state, latest) is None:
            raise ValueError("Held position price is missing; no trade")
        cache = state["histories"]
        for pair in selected_pairs:
            if pair not in latest:
                continue
            old = cache.get(pair)
            when = as_date(old.get("fetchedAt")) if old else None
            if when and (t - when).total_seconds() < 3600:
                continue
            try:
                points = closes(market.candles(pair), t, rate)
                if len(points) >= 60:
                    cache[pair] = {"fetchedAt": stamp(t), "prices": points}
            except Exception:
                pass  # no chart = no new signal; never generate fake candles
        for symbol in list(cache):
            if symbol not in selected_pairs:
                cache.pop(symbol, None)
        state["tracked"] = len(eligible_pairs)
        state["screened"] = len(latest)
        state["historyPairs"] = sum(
            1 for pair in latest if len(cache.get(pair, {}).get("prices", [])) >= 60
        )
        before = equity(state, latest)
        update_price_extremes(state, latest)
        state["peakEquityTry"] = max(before, state["peakEquityTry"])
        day = t.strftime("%Y-%m-%d")
        if state["day"] != day:
            state["day"] = day
            state["todayOrders"] = 0
        planned = assess_decision(state, latest, t)
        planned, ai_meta = apply_ai_brain(
            planned, state, api_key=os.environ.get("GROQ_API_KEY", ""),
            model=os.environ.get("GROQ_MODEL", "openai/gpt-oss-20b"))
        state["aiBrain"] = ai_meta
        state["decisionPlan"] = {
            key: value for key, value in planned.items()
            if key not in ("order", "aiChoices")
        }
        state["decisionPlan"]["aiBrain"] = ai_meta
        state["decisionPlan"]["universe"] = len(eligible_pairs)
        state["decisionPlan"]["historyPairs"] = state["historyPairs"]
        choice = planned["order"]
        if choice:
            pair, side, gross, reason = choice
            price = latest[pair]["priceTry"]
            if side == "short":
                open_short(state, t, pair, gross, price, reason)
            elif side == "cover":
                close_short(state, t, pair, price, reason)
            else:
                execute(state, t, pair, side, gross, price, reason)
        else:
            log(state, t, f"{len(eligible_pairs)} coin tarandı; "
                + planned["reason"])
        state["equityTry"] = equity(state, latest)
        # Store last observed marks of open paper positions for Flutter.
        active = set(state["holdings"]) | set(state.get("shorts", {}))
        state["marksTry"] = {
            pair: latest[pair]["priceTry"] for pair in active if pair in latest
        }
        record_performance(state, t)
        state["lastSuccessAt"] = stamp(t)
        state["lastError"] = None
    except Exception as exc:
        state["lastError"] = str(exc)[:200]
        state["decisionPlan"] = {
            "at": stamp(t), "action": "WAIT", "symbol": None,
            "amountTry": None, "score": None,
            "marketRegime": "VERİ HATASI",
            "reason": "Veri hatası nedeniyle yeni sanal emir engellendi",
            "reviewed": 0, "candidates": [],
        }
        log(state, t, "İşlem yapılmadı: piyasa verisi hatası. " + state["lastError"])
    return state

def record_trigger(state, t, event):
    """Record real GitHub event; never confuse push with cron."""
    if event not in ("schedule", "push", "workflow_dispatch"):
        return state
    state["lastTriggerEvent"] = event
    state["lastTriggerAt"] = stamp(t)
    if event == "schedule":
        state["lastScheduledTriggerAt"] = stamp(t)
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--mode", choices=("run", "pause", "resume", "reset"),
                        default="run")
    args = parser.parse_args()
    t = now_utc()
    state = load(args.state)
    if args.mode == "pause":
        state["enabled"] = False
        log(state, t, "Sunucu sanal botu durduruldu.")
    elif args.mode == "resume":
        state["enabled"] = True
        log(state, t, "Sunucu sanal botu etkinleştirildi.")
    elif args.mode == "reset":
        state = fresh_state()
        log(state, t, "Ayrı sunucu sanal kasası 650 TL'ye sıfırlandı.")
    else:
        state = record_trigger(state, t, os.getenv("TRIGGER_EVENT", ""))
        state = cycle(state, Market(), t)
    save(args.state, state)
    print(json.dumps({
        "enabled": state["enabled"], "cashTry": round(state["cashTry"], 4),
        "equityTry": round(state["equityTry"], 4),
        "lastSuccessAt": state["lastSuccessAt"],
        "lastError": state["lastError"], "trades": len(state["trades"])
    }, ensure_ascii=False))

if __name__ == "__main__":
    main()
