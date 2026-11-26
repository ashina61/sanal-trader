"""BTC-adjusted residual reversal: shared causal historical/live signal.

Inspired by statistical-arbitrage literature, not a reproduction or proof.
A single directional position is NOT a hedged pairs trade. No future bars
enter signal construction, and no synthetic wallet is maintained.
"""
import math
import statistics

LANES = ("relative_reclaim", "relative_fade")
LOOKBACK = 65
COST_PCT = .30
TARGET = 2.0
STOP = 1.0


def signal(coin, btc):
    """Only aligned CLOSED 15m prices. Estimate beta before the dislocation."""
    if len(coin) < LOOKBACK or len(btc) < LOOKBACK:
        return None
    p, b = coin[-LOOKBACK:], btc[-LOOKBACK:]
    if any(not math.isfinite(x) or x <= 0 for x in p+b):
        return None
    r = [math.log(y/x)*100 for x,y in zip(p,p[1:])]
    m = [math.log(y/x)*100 for x,y in zip(b,b[1:])]
    base_r, base_m = r[:-5], m[:-5]
    variance = statistics.variance(base_m)
    if variance < .0001:
        return None
    beta = statistics.covariance(base_r, base_m)/variance
    if not .15 <= beta <= 3:
        return None
    residuals = [x-beta*y for x,y in zip(r,m)]
    history = [sum(residuals[i-4:i]) for i in range(4,len(base_r)+1)]
    sd = statistics.stdev(history)
    if sd < .15 or sd > 4:
        return None
    deviation = sum(residuals[-5:-1])-statistics.mean(history)
    z = deviation/sd
    reversal = residuals[-1]
    # Absolute room must cover costs, with a small observed reversal rather
    # than blindly buying a dip or shorting a rally.
    if abs(deviation) < .8 or abs(z) > 4.5:
        return None
    if z <= -1.8 and .10 <= reversal <= .65*abs(deviation) and r[-1] > 0 and sum(m[-4:]) > -1.5:
        return ("relative_reclaim", "BUY", round(abs(z),4))
    if z >= 1.8 and -.65*abs(deviation) <= reversal <= -.10 and r[-1] < 0 and sum(m[-4:]) < 1.5:
        return ("relative_fade", "SHORT", round(abs(z),4))
    return None


def replay(data):
    """Chronological 70/30 split; next close entry, then observed exits.

    At most one open signal per lane per symbol; no portfolio-return claim.
    Development and holdout remain separate, boundary crossings are purged.
    """
    if "BTCUSDT" not in data or len(data) < 2:
        raise ValueError("BTC and one altcoin required")
    times = sorted(set.intersection(*(set(v) for v in data.values())))
    if len(times) < 400 or any(y-x != 900000 for x,y in zip(times,times[1:])):
        raise ValueError("Insufficient or gappy aligned 15m candles")
    split = int(.7*len(times))
    btc = [data["BTCUSDT"][t] for t in times]
    results = {lane: {"development": [], "holdout": []} for lane in LANES}
    for sym, rows in data.items():
        if sym == "BTCUSDT":
            continue
        prices = [rows[t] for t in times]
        next_allowed = {lane: LOOKBACK-1 for lane in LANES}
        for i in range(LOOKBACK-1,len(times)-5):
            found = signal(prices[i-LOOKBACK+1:i+1],btc[i-LOOKBACK+1:i+1])
            if not found:
                continue
            lane, action, _ = found
            if i < next_allowed[lane]:
                continue
            entry = i+1
            direction = 1 if action == "BUY" else -1
            for j in range(entry+1,entry+5):
                net = direction*(prices[j]/prices[entry]-1)*100-COST_PCT
                if net >= TARGET or net <= -STOP or j == entry+4:
                    break
            next_allowed[lane] = j+1
            if i < split <= j:
                continue
            results[lane]["development" if i<split else "holdout"].append(net)
    def metrics(values):
        gains=sum(x for x in values if x>0)
        losses=-sum(x for x in values if x<0)
        return {"samples":len(values),
                "avgNetPct":round(statistics.mean(values),4) if values else None,
                "winRatePct":round(100*sum(x>0 for x in values)/len(values),2) if values else None,
                "profitFactor":round(gains/losses,4) if losses else None}
    return {"status":"HISTORICAL_RESEARCH_ONLY","bars":len(times),
            "symbols":sorted(data),"holdoutStartsMs":times[split],
            "costPct":COST_PCT,"nextCloseEntry":True,
            "lanes":{k:{p:metrics(v) for p,v in parts.items()} for k,parts in results.items()},
            "limitations":["15m closes only; no intrabar fill, no funding or live depth",
                           "Directional residual strategy, not hedged pairs trading",
                           "No portfolio return or automatic promotion; correlated samples"]}


if __name__ == "__main__":
    import json
    from concurrent.futures import ThreadPoolExecutor
    from backend.walk_forward import fetch_klines
    symbols=("BTCUSDT","ETHUSDT","SOLUSDT","BNBUSDT","XRPUSDT","DOGEUSDT","ADAUSDT","LINKUSDT")
    with ThreadPoolExecutor(max_workers=4) as pool:
        data={symbol:dict(rows) for symbol,rows in zip(symbols,pool.map(fetch_klines,symbols))}
    print(json.dumps(replay(data),ensure_ascii=False,indent=2,allow_nan=False))
