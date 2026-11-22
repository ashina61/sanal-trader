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
                holdings={}, trades=[], journal=[], day="", todayOrders=0,
                lastOrder={}, realizedTry=0.0, paidFeesTry=0.0, histories={},
                lastSuccessAt=None, lastRunAt=None, lastError=None,
                source="Binance public spot REST", lastDecision="İlk kontrol bekleniyor",
                tracked=0, cycles=0)

def load(path):
    if not path.exists():
        return fresh_state()
    obj = json.loads(path.read_text(encoding="utf-8"))
    if (obj.get("schema") != 1 or not isinstance(obj.get("holdings"), dict)
            or not isinstance(obj.get("trades"), list)
            or numeric(obj.get("cashTry")) is None
            or obj["cashTry"] < -1e-6):
        raise ValueError("Invalid persistent wallet; refusing reset")
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
    return total

def execute(state, t, symbol, side, amount, price, reason):
    if not (MIN_ORDER <= amount and math.isfinite(amount) and
            price > 0 and math.isfinite(price)):
        raise ValueError("Bad virtual order")
    holdings = state["holdings"]
    fee = amount * FEE
    quantity = amount / price
    realized = 0.0
    if side == "buy":
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

def pick(state, latest, t):
    if not state["enabled"] or state["todayOrders"] >= 8:
        return None
    total = equity(state, latest)
    if total is None or total <= 0:
        return None
    def cooled(pair):
        d = as_date(state["lastOrder"].get(pair))
        return d is None or (t - d).total_seconds() >= 1800

    # Exits must still be possible during a portfolio drawdown.
    for pair, pos in state["holdings"].items():
        q = latest.get(pair)
        if q is None:
            continue
        amt = pos["quantity"] * q["priceTry"]
        if amt < MIN_ORDER:
            continue
        cost = pos["costTry"] / pos["quantity"]
        percent = q["priceTry"] / cost - 1
        tech = indicators(state["histories"].get(pair, {}).get("prices", []))
        if percent <= -.06:
            return pair, "sell", amt, "Sanal zarar koruması"
        if percent >= .08:
            return pair, "sell", amt, "Sanal kâr hedefi"
        if cooled(pair) and tech and tech["score"] < -.5:
            return pair, "sell", amt, "Negatif momentum"

    if total < state["peakEquityTry"] * .88:
        return None
    exposure = total - state["cashTry"]
    btc = indicators(state["histories"].get("BTCUSDT", {}).get("prices", []))
    choices = []
    for pair, q in latest.items():
        if not cooled(pair):
            continue
        tech = indicators(state["histories"].get(pair, {}).get("prices", []))
        if tech is None or tech["direction"] == "down" or tech["score"] < .55:
            continue
        if tech["volatility"] > 18:
            continue
        if pair != "BTCUSDT" and btc and btc["direction"] == "down":
            continue
        price = q["priceTry"]
        own = state["holdings"].get(pair, {}).get("quantity", 0) * price
        upper = min(total * .12, state["cashTry"] / (1 + FEE),
                    (state["cashTry"] - total * .30) / (1 + FEE),
                    total * .25 - own, total * .65 - exposure)
        riskfactor = .4 if tech["volatility"] > 9 else (
            .65 if tech["volatility"] > 6 else 1.0)
        amt = math.floor(upper * riskfactor * 100) / 100
        if amt >= MIN_ORDER:
            choices.append((tech["score"], pair, amt, tech))
    if not choices:
        return None
    score, pair, amt, tech = max(choices)
    return pair, "buy", amt, f"Trend {tech['direction']}, puan {score:.2f}"

def cycle(state, market, t):
    state = json.loads(json.dumps(state))
    state["lastRunAt"] = stamp(t)
    state["cycles"] += 1
    if not state.get("enabled", False):
        log(state, t, "Sunucu botu duraklatılmış.")
        return state
    last = as_date(state.get("lastSuccessAt"))
    if last and (t - last).total_seconds() < 150:
        log(state, t, "Tekrarlanan kontrol atlandı.")
        return state
    try:
        lookup, rate = quotes(market.tickers(), t)
        eligible_pairs = [v for v in lookup.values() if eligible(v["symbol"])
                          and v["volume"] >= 1_000_000]
        eligible_pairs.sort(key=lambda x: x["volume"], reverse=True)
        if not eligible_pairs:
            raise ValueError("No liquid spot quotes")
        # Whole market discovered; only most liquid and held coins need candle calls.
        selected_pairs = {v["symbol"] for v in eligible_pairs[:24]}
        selected_pairs.update(x for x in CORE if x in lookup)
        selected_pairs.update(state["holdings"].keys())
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
        before = equity(state, latest)
        state["peakEquityTry"] = max(before, state["peakEquityTry"])
        day = t.strftime("%Y-%m-%d")
        if state["day"] != day:
            state["day"] = day
            state["todayOrders"] = 0
        choice = pick(state, latest, t)
        if choice:
            pair, side, gross, reason = choice
            execute(state, t, pair, side, gross, latest[pair]["priceTry"], reason)
        else:
            log(state, t, f"{len(eligible_pairs)} coin tarandı; "
                "güvenli sanal emir sinyali oluşmadı.")
        state["equityTry"] = equity(state, latest)
        state["lastSuccessAt"] = stamp(t)
        state["lastError"] = None
    except Exception as exc:
        state["lastError"] = str(exc)[:200]
        log(state, t, "İşlem yapılmadı: piyasa verisi hatası. " + state["lastError"])
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
