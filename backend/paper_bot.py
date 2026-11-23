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
from backend.context_learning import (context_key, adjustment as context_adjustment,
    record_entry as context_record_entry, record_exit as context_record_exit)
from backend.news_radar import (fetch_rss, news_snapshot, entry_alert,
    REFRESH_INTERVAL_SECONDS)
from backend.market_breadth import market_breadth
from backend.scan_engine import fetch_candle_batch
from backend.evidence_guard import entry_gate, gate_summary
from backend.risk_feedback import (loss_reentry_cooldown, broad_risk_on,
    short_size_multiplier, short_reversal_exit, spot_trend_failure_exit,
    spot_profit_lock_exit, position_monitor)
from backend.shadow_validation import (migrate as migrate_forward,
    settle as settle_forward, record as record_forward,
    summary as forward_summary, evidence_bias)
from backend.signal_learning import (minute_signal, setup_for, signal_bias,
    record_open, record_close)

from backend.short_positions import (short_value, exposure, open_short,
    close_short, learn_closed_direction, direction_edge)

UTC = dt.timezone.utc
INITIAL = 650.0
FEE = .001
MIN_ORDER = 5.0

# No fixed trade quota: signal, verified data and cash/exposure are the gates.
MAX_ENTRY_EXPOSURE = .78
MIN_ENTRY_CASH_RESERVE = .20
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
                lastScheduledTriggerAt=None, intraday={}, peakMarksTry={},
                troughMarksTry={}, equityHistory=[], performance={},
                micro={}, signalStats={}, openSignals={},
                contextStats={}, openContexts={}, newsPulse={},
                marketPulse={}, forwardEvidence={})

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
    obj.setdefault("intraday", {})
    obj.setdefault("micro", {})
    obj.setdefault("signalStats", {})
    obj.setdefault("openSignals", {})
    obj.setdefault("contextStats", {})
    obj.setdefault("openContexts", {})
    obj.setdefault("newsPulse", {})
    obj.setdefault("marketPulse", {})
    migrate_forward(obj)
    if any(not isinstance(obj[field], dict) for field in
           ("intraday", "micro", "signalStats", "openSignals",
            "contextStats", "openContexts", "newsPulse", "marketPulse")):
        raise ValueError("Invalid minute/learning paper cache")
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

    def candles_fast(self, symbol):
        return self.request("/api/v3/klines",
                            {"symbol": symbol, "interval": "15m", "limit": 96})

    def candles_minute(self, symbol):
        return self.request("/api/v3/klines",
                            {"symbol": symbol, "interval": "1m", "limit": 65})

    def news(self, t):
        articles, failures = fetch_rss(t)
        return news_snapshot(articles, t, failures)

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

def fast_momentum(series, mark):
    """1h/4h momentum from actual closed 15m bars and fresh market mark."""
    if not isinstance(series, list) or len(series) < 20:
        return None
    recent = series[-20:]
    if not all(numeric(x) and x > 0 for x in recent):
        return None
    if numeric(mark) is None or mark <= 0 or abs(mark / recent[-1] - 1) > .08:
        return None
    return {"momentum1h": 100 * (mark / series[-4] - 1),
            "momentum4h": 100 * (mark / series[-16] - 1)}


def entry_quality_score(tech, fast, micro, mode, learned=0.0):
    """Rank validated candidates by trend quality, follow-through and risk.

    This only sorts risk-approved spot/SHORT opportunities. It never turns
    an unapproved setup into an order or predicts an unobserved return.
    """
    sign = 1 if mode == "buy" else -1
    score = sign * tech["score"] + learned
    if fast is not None:
        score += min(.16, max(0, sign * fast["momentum1h"]) * .13)
        score += min(.12, max(0, sign * fast["momentum4h"]) * .035)
    if micro is not None:
        score += min(.12, max(0, sign * micro["momentum5"]) * .18)
        score += min(.10, max(0, sign * micro["momentum15"]) * .06)
        if micro["breakout"] if mode == "buy" else micro["breakdown"]:
            score += .03
    # High-noise coins and already extended hourly runs pay a ranking cost.
    score -= min(.25, max(0, tech["volatility"]) * .025)
    score -= min(.12, max(0, abs(tech["momentum6"]) - 2.5) * .035)
    return round(score, 4)


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
    log(state, t, ("Sanal SPOT AL" if side == "buy" else "Sanal SPOT SAT") +
        f" {symbol}: {amount:.2f} TL; {reason}")
    return rec

def assess_decision(state, latest, t, research_only=False):
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
        return last is None or (t - last).total_seconds() >= 600

    def quick(pair):
        record = state.get("intraday", {}).get(pair, {})
        when = as_date(record.get("fetchedAt"))
        if when is None or when > t or (t - when).total_seconds() > 1500:
            return None
        return fast_momentum(
            record.get("prices", []), latest.get(pair, {}).get("priceTry"))

    def minute(pair):
        record = state.get("micro", {}).get(pair, {})
        fetched = as_date(record.get("fetchedAt"))
        if fetched is None or fetched > t or (t - fetched).total_seconds() > 420:
            return None
        return minute_signal(
            record.get("prices", []), latest.get(pair, {}).get("priceTry"))

    def holding_age(pair, side):
        if side == "short":
            moment = state.get("shorts", {}).get(pair, {}).get("openedAt")
        else:
            moment = state.get("openContexts", {}).get(pair, {}).get("at")
            if not moment:
                moment = next((entry.get("at") for entry in state.get("trades", [])
                    if entry.get("symbol") == pair and entry.get("side") == "buy"), None)
        opened = as_date(moment)
        return (t - opened).total_seconds() if opened and opened <= t else None

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
        elif adverse >= .045:
            exits.append((120 + adverse, pair, "cover", amount,
                          f"SHORT zarar kes: ters hareket %{adverse*100:.1f}", technical))
        elif (minute(pair) is not None
              and minute(pair)["momentum5"] >= 1.5
              and minute(pair)["momentum15"] >= 1.5
              and adverse >= .012):
            exits.append((115, pair, "cover", amount,
                          "SHORT gözlenen 1dk ani ters yükseliş koruması", technical))
        elif adverse <= -.035:
            exits.append((100 - adverse, pair, "cover", amount,
                          f"SHORT kâr al: düşüş %{abs(adverse)*100:.1f}", technical))
        elif (state.get("troughMarksTry", {}).get(pair) is not None
              and 1 - state["troughMarksTry"][pair] / entry >= .015
              and adverse <= -.004
              and current / state["troughMarksTry"][pair] - 1 >= .009):
            exits.append((91, pair, "cover", amount,
                          "SHORT takip eden kâr koruması: dipten dönüş", technical))
        elif (minute(pair) is not None
              and minute(pair)["momentum5"] >= .65
              and adverse <= -.006):
            exits.append((94, pair, "cover", amount,
                          "SHORT gözlenen 1dk kâr koruyan dönüş", technical))
        elif (cooled(pair) and short_reversal_exit(
                holding_age(pair, "short"), adverse, quick(pair),
                minute(pair), state.get("marketPulse", {}),
                plan["marketRegime"])):
            exits.append((109, pair, "cover", amount,
                "SHORT rejim tersine döndü: 1dk+15dk+geniş piyasa yükseliş onayı",
                technical))
        elif (cooled(pair) and quick(pair) is not None
              and quick(pair)["momentum1h"] >= .75 and adverse <= -.006):
            exits.append((85, pair, "cover", amount,
                          "15dk mumları: SHORT aleyhine hızlı dönüş", technical))
        elif (cooled(pair) and technical and technical["score"] >= .50
              and (adverse >= .025 or adverse <= -.005)):

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
        if move <= -.045:
            exits.append((120 - move, pair, "sell", amount,
                          f"Spot zarar kes: düşüş %{abs(move)*100:.1f}", technical))
        elif (minute(pair) is not None
              and minute(pair)["momentum5"] <= -1.5
              and minute(pair)["momentum15"] <= -1.5
              and move <= -.012):
            exits.append((115, pair, "sell", amount,
                          "SPOT gözlenen 1dk ani düşüş koruması", technical))
        elif move >= .035:
            exits.append((100 + move, pair, "sell", amount,
                          f"Spot kâr al: yükseliş %{move*100:.1f}", technical))
        elif (state.get("peakMarksTry", {}).get(pair) is not None
              and state["peakMarksTry"][pair] / cost - 1 >= .015
              and move >= .004
              and quote["priceTry"] / state["peakMarksTry"][pair] - 1 <= -.009):
            exits.append((91, pair, "sell", amount,
                          "SPOT takip eden kâr koruması: zirveden dönüş", technical))
        elif (cooled(pair)
              and state.get("peakMarksTry", {}).get(pair) is not None
              and spot_profit_lock_exit(
                holding_age(pair, "buy"), move,
                state["peakMarksTry"][pair] / cost - 1,
                quote["priceTry"] / state["peakMarksTry"][pair] - 1,
                minute(pair))):
            exits.append((92, pair, "sell", amount,
                "SPOT gözlenen zirve + 1dk dönüş: kârı koruyarak çıkış",
                technical))
        elif (minute(pair) is not None
              and minute(pair)["momentum5"] <= -.65
              and move >= .006):
            exits.append((94, pair, "sell", amount,
                          "SPOT gözlenen 1dk kâr koruyan dönüş", technical))
        elif (cooled(pair) and spot_trend_failure_exit(
                holding_age(pair, "buy"), move, quick(pair),
                minute(pair), technical)):
            exits.append((87, pair, "sell", amount,
                "SPOT uzun süreli 1dk+15dk+1s trend bozulması: risk azaltımı",
                technical))
        elif (cooled(pair) and quick(pair) is not None
              and quick(pair)["momentum1h"] <= -.75 and move >= .006):
            exits.append((85, pair, "sell", amount,
                          "15dk mumları: SPOT kâr koruyan hızlı çıkış", technical))
        elif (cooled(pair) and technical and technical["score"] < -.50
              and (move >= .005 or move <= -.025)):

            exits.append((80 - technical["score"], pair, "sell", amount,
                          "Momentum düşüşe döndü; açık SPOT satılıyor", technical))

    # Only severe CONFIRMED weakness can free a saturated paper wallet.
    # No routine -0.35% churn: fees made repeated tiny exits unprofitable.
    # One such defensive early exit per UTC day, no automatic replacement.
    used_now = exposure(state, latest)
    if used_now is not None and used_now >= total * .64:
        recent_exits = [
            as_date(tr.get("at")) for tr in state.get("trades", [])
            if isinstance(tr, dict) and
            str(tr.get("reason", "")).startswith("Risk azaltımı: ")
        ]
        recent_exits = [at for at in recent_exits
                        if at and at.date() == t.date()]
        if not recent_exits:
            for pair, pos in state["holdings"].items():
                mark = latest.get(pair, {}).get("priceTry")
                if not mark or pos.get("quantity", 0) <= 0:
                    continue
                last_open = as_date(state.get("lastOrder", {}).get(pair))
                if last_open is None or (t - last_open).total_seconds() < 10800:
                    continue
                fast = quick(pair)
                tech = current_tech(pair)
                if fast is None or tech is None:
                    continue
                entry = pos["costTry"] / pos["quantity"]
                pnl = mark / entry - 1
                if (-.045 < pnl <= -.025
                        and fast["momentum4h"] <= -1.5
                        and fast["momentum1h"] <= -.35
                        and tech["momentum6"] < 0):
                    exits.append((82, pair, "sell", pos["quantity"] * mark,
                        "Risk azaltımı: uzun süren zayıf 15dk momentum "
                        "ile dolu portföyün zararı sınırlanıyor", tech))

    plan["openPositionsChecked"] = (
        len(state["holdings"]) + len(state.get("shorts", {})))
    plan["protectiveExitCandidates"] = len(exits)
    if exits and not research_only:
        priority, pair, side, amount, reason, technical = max(
            exits, key=lambda item: (item[0], item[3]))
        plan["reviewed"] = len(latest)
        return choose(pair, side, amount, reason,
                      technical["score"] if technical else None)

    # Controls below block NEW positions only, never protective exits.
    if not research_only and total < state.get("peakEquityTry", total) * .88:
        return wait("Portföy gerilemesi %12'yi geçti; yeni risk durduruldu")
    used = exposure(state, latest)
    if used is None:
        return wait("Açık pozisyonlar için güvenilir piyasa değeri yok")

    # Rotate ONLY a net-profitable held spot position. Chasing another
    # token by selling a losing position incurred four losing closes and
    # repeated fees in the first paper session. Protect cash first.
    if (not research_only and used >= total * .70
            and btc and btc["direction"] != "down"):
        rotation_times = [
            as_date(order.get("at")) for order in state.get("trades", [])
            if isinstance(order, dict)
            and str(order.get("reason", "")).startswith("Portföy rotasyonu")
        ]
        rotation_times = [when for when in rotation_times
                          if when is not None and when.date() == t.date()]
        recently_rotated = any(
            (t - when).total_seconds() < 5400 for when in rotation_times)
        if len(rotation_times) < 1 and not recently_rotated:
            leaders = []
            for pair in latest:
                if (pair in state["holdings"] or pair in state.get("shorts", {})
                        or not cooled(pair)):
                    continue
                tech = current_tech(pair)
                if not tech or tech["volatility"] > 9:
                    continue
                fast = quick(pair)
                if (tech["direction"] == "up" and tech["score"] >= .85
                        and tech["momentum6"] >= 1.0
                        and (fast is None or
                             (fast["momentum1h"] >= .2 and
                              fast["momentum4h"] >= .5))):
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
                    fast = quick(pair)
                    hourly_fading = (tech["score"] <= .35 and tech["momentum6"] < 0)
                    fast_fading = fast is not None and fast["momentum1h"] <= -.45
                    if (.007 <= pnl_ratio <= .03
                            and (hourly_fading or fast_fading)
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

    if not research_only and used >= total * MAX_ENTRY_EXPOSURE:
        return wait("SPOT+SHORT pozisyon payı %78 seviyesinde; "
                    "zararına rotasyon yapılmıyor")
    if not research_only and state["cashTry"] <= total * MIN_ENTRY_CASH_RESERVE:
        return wait("Yeni giriş için kullanılabilir sanal nakit yetersiz")

    candidates = []
    reasons = {}
    def rejected(label):
        reasons[label] = reasons.get(label, 0) + 1
    for pair, quote in latest.items():
        if (not research_only and
                (pair in state["holdings"] or pair in state.get("shorts", {}))):
            rejected("Zaten açık pozisyon")
            continue
        if not research_only and not cooled(pair):
            rejected("Aynı coin için 10 dk dönüş bekleme")
            continue
        if not research_only and loss_reentry_cooldown(state, pair, t):
            rejected("Zarar sonrası 90dk yeniden giriş beklemesi")
            continue
        tech = current_tech(pair)
        if tech is None:
            rejected("Yetersiz / eski mum")
            continue
        if entry_alert(state.get("newsPulse", {}), pair, t):
            rejected("Yakın tarihli olumsuz haber uyarısı")
            continue
        if tech["volatility"] > 7.5:
            rejected("Fazla oynaklık / komisyon riski")
            continue
        plan["reviewed"] += 1
        # The observed movement must exceed round-trip 0.2% fees plus
        # a safety buffer. Trading without a signal is not learning.
        if abs(tech["momentum6"]) < .6:
            rejected("Zayıf 6s momentum")
            continue
        fast = quick(pair)
        micro = minute(pair)
        if state.get("microSourceConfigured") and micro is None:
            rejected("Gerçek 1dk onayı yok")
            continue
        if micro is not None:
            if (abs(micro["momentum5"]) > 2.4 or
                    abs(micro["momentum15"]) > 5.5):
                rejected("Ani pump/crash kovalanmıyor")
                continue
            if (tech["direction"] == "up"
                    and (micro["momentum5"] < .12
                         or micro["momentum15"] < .28
                         or micro["upBars5"] < 3)):
                rejected("1dk spot alım onayı yok")
                continue
            if (tech["direction"] == "down"
                    and (micro["momentum5"] > -.12
                         or micro["momentum15"] > -.28
                         or micro["downBars5"] < 3)):
                rejected("1dk short onayı yok")
                continue
        # Only real cached 15m candles can confirm a live minute signal.
        if state.get("intraday") and fast is None:
            rejected("Taze 15dk mum yok")
            continue
        if fast is not None:
            if (tech["direction"] == "up"
                    and (fast["momentum1h"] < .15 or
                         fast["momentum4h"] < .60)):
                rejected("15dk ters trend")
                continue
            if (tech["direction"] == "down"
                    and (fast["momentum1h"] > -.15 or
                         fast["momentum4h"] > -.60)):
                rejected("15dk ters trend")
                continue
            if (abs(fast["momentum1h"]) > 1.8 or
                    abs(fast["momentum4h"]) > 5):
                rejected("Aşırı hızlı yükseliş/düşüş kovalama")
                continue
        if pair != "BTCUSDT" and btc is None:
            rejected("BTC grafik verisi yok")
            continue
        mode = None
        if (tech["direction"] == "up" and tech["score"] >= .75
                and .65 <= tech["momentum6"] <= 5.0):
            relative_strength = (micro is not None
                and micro["momentum15"] >= .9
                and fast is not None and fast["momentum1h"] >= .55)
            if pair == "BTCUSDT" or btc["direction"] != "down" or relative_strength:
                mode = "buy"
            else:
                rejected("BTC rejimi")
        elif (tech["direction"] == "down" and tech["score"] <= -.75
                and -5.0 <= tech["momentum6"] <= -.65):
            relative_weakness = (micro is not None
                and micro["momentum15"] <= -.9
                and fast is not None and fast["momentum1h"] <= -.55)
            if pair == "BTCUSDT" or btc["direction"] != "up" or relative_weakness:
                mode = "short"
            else:
                rejected("BTC rejimi")
        else:
            rejected("Zayıf trend/sinyal")
        if mode is None:
            continue
        if (not research_only and entry_gate(
                state, "BUY" if mode == "buy" else "SHORT")["blocked"]):
            rejected("Son gözlenen sinyal sonuçları negatif; yeni risk bekletildi")
            continue
        if (not research_only and mode == "short" and
                broad_risk_on(state.get("marketPulse", {}),
                              btc["direction"] if btc else None)):
            rejected("Piyasa geneli yükselirken yeni SHORT engeli")
            continue
        upper = min(
            total * .12, state["cashTry"] / 1.001,
            (state["cashTry"] - total * MIN_ENTRY_CASH_RESERVE) / 1.001,
            total * .25, total * MAX_ENTRY_EXPOSURE - used,
        )
        scale = (.4 if tech["volatility"] > 9 else
                 .65 if tech["volatility"] > 6 else 1.0)
        if mode == "short":
            scale *= short_size_multiplier(state)
        amount = (MIN_ORDER if research_only else
                  math.floor(max(0.0, upper) * scale * 100) / 100)
        if amount < MIN_ORDER:
            rejected("Kullanılabilir sanal tutar")
            continue
        direction = "long" if mode == "buy" else "short"
        setup = setup_for(micro, mode)
        learned_context = context_key(mode, plan["marketRegime"],
                                      tech["volatility"])
        score = entry_quality_score(
            tech, fast, micro, mode,
            direction_edge(state, direction)
            + signal_bias(state, mode, setup)
            + context_adjustment(state, learned_context)
            + evidence_bias(state, "BUY" if mode == "buy" else "SHORT",
                            plan["marketRegime"]))
        if micro is not None:
            evidence = min(abs(micro["momentum15"]),
                           abs(tech["momentum6"]) / 2)
            if evidence < .35:
                rejected("Sinyal komisyon üstü değil")
                continue
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
            "momentum1hPct": round(quick(pair)["momentum1h"], 2)
                if quick(pair) is not None else None,
            "momentum5mPct": round(minute(pair)["momentum5"], 3)
                if minute(pair) is not None else None,
            "setupTag": setup_for(minute(pair), side),
            "contextKey": context_key(side, plan["marketRegime"],
                                      tech["volatility"]),
            "policyExcluded": bool(
                side == "short" and broad_risk_on(
                    state.get("marketPulse", {}),
                    btc["direction"] if btc else None)),
        }
        for score, pair, side, _, tech in candidates[:8]
    ]
    if research_only:
        return wait("Tek sanal kasa dışında emir üretmeyen sinyal gözlemi")
    if not candidates:
        primary = next(iter(plan["rejectReasons"].items()), None)
        detail = f" En sık neden: {primary[0]} ({primary[1]} coin)." if primary else ""
        return wait("Yeterli trend/momentum, maliyet payı ve risk koşulu oluşmadı." + detail)
    plan["aiChoices"] = [
        {"symbol": pair, "action": "BUY" if side == "buy" else "SHORT",
         "amountTry": amount, "score": round(score, 3),
         "momentum6Pct": round(tech["momentum6"], 2),
         "volatilityPct": round(tech["volatility"], 2),
         "momentum1hPct": round(quick(pair)["momentum1h"], 2)
             if quick(pair) is not None else None,
         "momentum5mPct": round(minute(pair)["momentum5"], 3)
             if minute(pair) is not None else None,
         "setupTag": setup_for(minute(pair), side),
         "contextKey": context_key(side, plan["marketRegime"],
                                   tech["volatility"])}
        for score, pair, side, amount, tech in candidates[:8]
    ]
    score, pair, side, amount, tech = candidates[0]
    plan["setupTag"] = setup_for(minute(pair), side)
    plan["contextKey"] = context_key(side, plan["marketRegime"],
                                     tech["volatility"])
    mode = "SPOT AL" if side == "buy" else "SANAL 1x SHORT"
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
    if last and (t - last).total_seconds() < 75:
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
        due_hourly = [
            pair for pair in selected_pairs if pair in latest and
            (not cache.get(pair) or
             not as_date(cache[pair].get("fetchedAt")) or
             (t - as_date(cache[pair].get("fetchedAt"))).total_seconds() >= 3600)
        ]
        hour_bars, hour_stats = fetch_candle_batch(
            market.candles, due_hourly,
            lambda rows: closes(rows, t, rate), minimum=60)
        for pair, prices in hour_bars.items():
            cache[pair] = {"fetchedAt": stamp(t), "prices": prices}
        for symbol in list(cache):
            if symbol not in selected_pairs:
                cache.pop(symbol, None)
        # Add real closed 15m candles for liquid + high-momentum symbols and
        # held positions. Bounded workload; hourly trend still anchors trades.
        fast_cache = state.setdefault("intraday", {})
        # Analyze every shortlisted trading candidate on the same timeframes.
        # Previously only a subset had 15m candles, making others impossible
        # to enter despite passing the main liquidity/mover selection.
        fast_symbols = set(latest)
        fast_symbols.update(state["holdings"].keys())
        fast_symbols.update(state.get("shorts", {}).keys())
        fast_symbols.intersection_update(latest)
        fast_provider = getattr(market, "candles_fast", None)
        fast_stats = {"requested": 0, "valid": 0, "failed": 0, "elapsedSec": 0.0}
        if callable(fast_provider):
            due_fast = [
                pair for pair in fast_symbols if
                not as_date(fast_cache.get(pair, {}).get("fetchedAt")) or
                (t - as_date(fast_cache[pair]["fetchedAt"])).total_seconds() >= 720
            ]
            fast_bars, fast_stats = fetch_candle_batch(
                fast_provider, due_fast,
                lambda rows: closes(rows, t, rate), minimum=20)
            for pair, prices in fast_bars.items():
                fast_cache[pair] = {
                    "fetchedAt": stamp(t), "prices": prices,
                }
        for pair in list(fast_cache):
            if pair not in fast_symbols:
                fast_cache.pop(pair, None)
        state["intradayPairs"] = sum(
            len(fast_cache.get(pair, {}).get("prices", [])) >= 20
            for pair in fast_symbols)

        # Closed one-minute candles: observed only at the GitHub run cadence.
        # No claim of fills between the observed ticks.
        minute_cache = state.setdefault("micro", {})
        # A global "1m required" gate must not silently exclude coins that
        # the fetch loop never attempted to cover.
        minute_symbols = set(latest)
        minute_symbols.update(state["holdings"])
        minute_symbols.update(state.get("shorts", {}))
        minute_symbols.intersection_update(latest)
        minute_provider = getattr(market, "candles_minute", None)
        state["microSourceConfigured"] = minute_provider is not None
        minute_stats = {"requested": 0, "valid": 0, "failed": 0,
                        "elapsedSec": 0.0}
        if callable(minute_provider):
            minute_bars, minute_stats = fetch_candle_batch(
                minute_provider, minute_symbols,
                lambda rows: closes(rows, t, rate), minimum=35)
            # Fail closed: never silently reuse 1m confirmation after an
            # individual endpoint fails. Held positions still have hard stops.
            for pair in minute_symbols:
                if pair in minute_bars:
                    minute_cache[pair] = {
                        "fetchedAt": stamp(t),
                        "prices": minute_bars[pair][-65:]}
                else:
                    minute_cache.pop(pair, None)
        for pair in list(minute_cache):
            if pair not in minute_symbols:
                minute_cache.pop(pair, None)
        state["minutePairs"] = sum(
            len(minute_cache.get(pair, {}).get("prices", [])) >= 35
            for pair in minute_symbols)
        state["tracked"] = len(eligible_pairs)
        state["screened"] = len(latest)
        state["scanStats"] = {
            "hourly": hour_stats, "fast15m": fast_stats,
            "minute1m": minute_stats,
            "publicRequests": sum(x["requested"] for x in
                 (hour_stats, fast_stats, minute_stats)),
            "candleElapsedSec": round(sum(x["elapsedSec"] for x in
                 (hour_stats, fast_stats, minute_stats)), 3),
            "workers": 6,
        }
        state["marketPulse"] = market_breadth(latest)
        state["historyPairs"] = sum(
            1 for pair in latest if len(cache.get(pair, {}).get("prices", [])) >= 60
        )
        before = equity(state, latest)
        # Research results use ONLY newly observed future quotes. No wallet
        # transaction, and a candidate cannot score at its entry timestamp.
        settle_forward(state, latest, t)
        update_price_extremes(state, latest)
        state["peakEquityTry"] = max(before, state["peakEquityTry"])
        # Headline polling is deliberately much slower than market polling:
        # RSS is best-effort context, never a reason to stop stop-loss exits.
        provider = getattr(market, "news", None)
        last_news_at = as_date(state.get("newsPulse", {}).get("checkedAt"))
        if callable(provider) and (last_news_at is None or
                (t - last_news_at).total_seconds() >= REFRESH_INTERVAL_SECONDS):
            try:
                state["newsPulse"] = provider(t)
            except Exception as exc:
                state["newsPulse"] = {
                    "checkedAt": stamp(t), "status": "UNAVAILABLE",
                    "headlines": [], "sourceCount": 0,
                    "failures": [type(exc).__name__],
                }
        day = t.strftime("%Y-%m-%d")
        if state["day"] != day:
            state["day"] = day
            state["todayOrders"] = 0
        planned = assess_decision(state, latest, t)
        if planned["order"]:
            # Scanning charts can take tens of seconds. NEVER simulate a fill
            # against the older pre-scan ticker. Reprice from a fresh public
            # snapshot and require the entire entry/exit decision to remain
            # valid at the observed execution mark, before asking the AI.
            fresh_lookup, fresh_fx = quotes(market.tickers(), t)
            latest = {
                pair: {
                    "symbol": pair, "priceTry": fresh_lookup[pair]["usdt"] * fresh_fx,
                    "volumeUsdt": fresh_lookup[pair]["volume"],
                    "change24h": fresh_lookup[pair]["change"],
                }
                for pair in latest if pair in fresh_lookup
            }
            refreshed_equity = equity(state, latest)
            if refreshed_equity is None:
                raise ValueError("Position quote missing during fill revalidation")
            update_price_extremes(state, latest)
            state["peakEquityTry"] = max(refreshed_equity, state["peakEquityTry"])
            planned = assess_decision(state, latest, t)
            planned["priceRechecked"] = True
        planned, ai_meta = apply_ai_brain(
            planned, state, api_key=os.environ.get("GROQ_API_KEY", ""),
            model=os.environ.get("GROQ_MODEL", "openai/gpt-oss-20b"))
        state["aiBrain"] = ai_meta
        # Independent observations from the SAME price/risk signal code:
        # research_only bypasses cash/exposure and exits but never places
        # another order, uses another wallet or invents prices.
        research_plan = assess_decision(state, latest, t, research_only=True)
        # Research probes are never filled. This annotation is ONLY to
        # distinguish how the AI treated the actual candidate, not an order.
        research_plan["action"] = planned.get("action")
        research_plan["symbol"] = planned.get("symbol")
        record_forward(state, latest, research_plan, t, ai_meta=ai_meta)
        state["decisionPlan"] = {
            key: value for key, value in planned.items()
            if key not in ("order", "aiChoices")
        }
        state["decisionPlan"]["aiBrain"] = ai_meta
        state["decisionPlan"]["universe"] = len(eligible_pairs)
        state["decisionPlan"]["historyPairs"] = state["historyPairs"]
        state["decisionPlan"]["intradayPairs"] = state.get("intradayPairs", 0)
        state["decisionPlan"]["minutePairs"] = state.get("minutePairs", 0)
        state["decisionPlan"]["signalStats"] = state.get("signalStats", {})
        state["decisionPlan"]["contextStats"] = state.get("contextStats", {})
        state["decisionPlan"]["forwardEvidence"] = forward_summary(state)
        state["decisionPlan"]["researchSignals"] = len(
            research_plan.get("candidates", []))
        state["decisionPlan"]["marketPulse"] = state.get("marketPulse", {})
        state["decisionPlan"]["scanStats"] = state.get("scanStats", {})
        state["decisionPlan"]["evidenceGuard"] = gate_summary(state)
        state["decisionPlan"]["newsStatus"] = state.get("newsPulse", {}).get("status", "UNAVAILABLE")
        state["decisionPlan"]["newsHeadlines"] = state.get("newsPulse", {}).get("headlines", [])[:6]
        state["decisionPlan"]["todayOrders"] = state["todayOrders"]
        state["decisionPlan"]["dailyLimit"] = None
        state["decisionPlan"]["strategy"] = "Adaptive v9 · transparent trade tape + fee-positive peak profit lock"
        choice = planned["order"]
        if choice:
            pair, side, gross, reason = choice
            price = latest[pair]["priceTry"]
            if side == "short":
                executed = open_short(state, t, pair, gross, price, reason)
            elif side == "cover":
                executed = close_short(state, t, pair, price, reason)
            else:
                executed = execute(state, t, pair, side, gross, price, reason)
            if side in ("buy", "short"):
                record_open(state, pair, side,
                            planned.get("setupTag") or "hourly",
                            gross, stamp(t))
                context_record_entry(state, pair, planned.get("contextKey"),
                                     gross, stamp(t))
            else:
                record_close(state, pair, executed["realizedPnlTry"])
                context_record_exit(state, pair, executed["realizedPnlTry"])
        else:
            log(state, t, f"{len(eligible_pairs)} coin tarandı; "
                + planned["reason"])
        state["equityTry"] = equity(state, latest)
        state["decisionPlan"]["positionHealth"] = position_monitor(
            state, latest, t)
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
