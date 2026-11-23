"""Read-only Solana/Base smart-wallet research radar.

An external, independently maintained on-chain indexer must supply the feed.
The feed's assertions are NOT independently proven by this module. Missing,
stale or unchecked data never produces an actionable signal or a paper order.
"""
import datetime as dt
import json
import math
import os
import re
import urllib.request

UTC = dt.timezone.utc
MAX_WALLETS = 15
WINDOW = dt.timedelta(minutes=20)
HISTORY = dt.timedelta(hours=24)
FEED_MAX_AGE = dt.timedelta(minutes=5)
STATS_MAX_AGE = dt.timedelta(hours=24)
MAX_FEED_BYTES = 1_000_000

_EVM = re.compile(r"0x[a-fA-F0-9]{40}\Z")
_EVM_TX = re.compile(r"0x[a-fA-F0-9]{64}\Z")
_SOL = re.compile(r"[1-9A-HJ-NP-Za-km-z]{32,44}\Z")
_SOL_TX = re.compile(r"[1-9A-HJ-NP-Za-km-z]{64,90}\Z")


def _date(value):
    if not isinstance(value, str):
        return None
    try:
        result = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return result.astimezone(UTC) if result.tzinfo else None
    except ValueError:
        return None


def _number(value):
    if isinstance(value, bool):
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (ValueError, TypeError, OverflowError):
        return None


def _address(chain, address, tx=False):
    pattern = (_EVM_TX if tx else _EVM) if chain == "base" else (
        _SOL_TX if tx else _SOL)
    return isinstance(address, str) and bool(pattern.fullmatch(address))


def _stamp(now):
    return now.astimezone(UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


def _prior(previous):
    p = previous if isinstance(previous, dict) else {}
    return {
        "seenTokens": dict(p.get("seenTokens", {})) if isinstance(
            p.get("seenTokens"), dict) else {},
        "seenSales": dict(p.get("seenSales", {})) if isinstance(
            p.get("seenSales"), dict) else {},
        "history": list(p.get("history", [])) if isinstance(
            p.get("history"), list) else [],
    }


def _snapshot(previous, now, status, reason, **fields):
    saved = _prior(previous)
    saved["history"] = [
        row for row in saved["history"][-80:]
        if isinstance(row, dict) and _date(row.get("at")) is not None
        and now - HISTORY <= _date(row["at"]) <= now
    ]
    return {
        "status": status, "reason": reason, "checkedAt": _stamp(now),
        "mode": "READ_ONLY_RESEARCH", "chains": ["solana", "base"],
        "walletCount": 0, "eventCount": 0, "newSignals": [],
        "saleAlerts": [], "sourceAsOf": None,
        "maxPositionPct": 7, "paperStopLossPct": -7,
        "signalsRequireApproval": True, "requiresPriceFeedForPaperFill": True,
        **saved, **fields,
    }


def read_feed(url, *, opener=None):
    """HTTPS JSON source configured via SMART_WALLET_FEED_URL; no hardcoded key."""
    if not isinstance(url, str) or not url.startswith("https://"):
        raise ValueError("HTTPS feed URL required")
    request = urllib.request.Request(url, headers={
        "Accept": "application/json", "User-Agent": "SanalTraderSmartMoney/1.0",
    })
    opening = opener or urllib.request.urlopen
    with opening(request, timeout=5) as response:
        body = response.read(MAX_FEED_BYTES + 1)
    if len(body) > MAX_FEED_BYTES:
        raise ValueError("Feed too large")
    decoded = json.loads(body.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("Feed root must be an object")
    return decoded


def _safe_token(event, chain):
    safety = event.get("safety")
    if not isinstance(safety, dict):
        return False
    liquid = _number(safety.get("liquidityUsd"))
    rise = _number(safety.get("priceChange60mPct"))
    if liquid is None or liquid < 200_000 or rise is None or rise > 30:
        return False
    if safety.get("lpLocked") is not True or safety.get("sellable") is not True:
        return False
    # Base smart contracts need their own verified mint/blacklist checks.
    if chain == "base":
        return (safety.get("contractSafetyVerified") is True
                and safety.get("contractMintDisabled") is True
                and safety.get("blacklistDisabled") is True)
    return (safety.get("mintAuthorityRevoked") is True
            and safety.get("freezeAuthorityRevoked") is True)


def _event(event, chain, wallet, now):
    if not isinstance(event, dict) or event.get("chain") != chain:
        return None
    at = _date(event.get("at"))
    token = event.get("tokenAddress")
    txid = event.get("txHash")
    if (not at or not now - HISTORY <= at <= now + dt.timedelta(seconds=30)
            or not _address(chain, token) or not _address(chain, txid, tx=True)
            or not isinstance(event.get("symbol"), str)
            or not 1 <= len(event["symbol"]) <= 24
            or not isinstance(event.get("wallet"), str)
            or event["wallet"].lower() != wallet.lower()):
        return None
    if event.get("verifiedSwap") is not True or event.get("transferOnly") is not False:
        return None
    side = event.get("side")
    if side not in ("BUY", "SELL"):
        return None
    if side == "BUY":
        if (event.get("newCapitalVerified") is not True
                or not _safe_token(event, chain)):
            return None
        funder = event.get("fundingGroup")
        if not isinstance(funder, str) or not funder.strip():
            return None
    return {**event, "_at": at, "_wallet": wallet.lower(),
            "_token": token.lower(), "_chain": chain}


def evaluate(feed, previous=None, now=None):
    """Analyze one externally attested on-chain snapshot, without any trades."""
    now = (now or dt.datetime.now(UTC)).astimezone(UTC)
    if not isinstance(feed, dict):
        return _snapshot(previous, now, "INVALID", "Akıllı cüzdan veri biçimi geçersiz")
    as_of = _date(feed.get("asOf"))
    if as_of is None or not dt.timedelta(0) <= now - as_of <= FEED_MAX_AGE:
        return _snapshot(previous, now, "STALE", "Veri eski veya zaman damgası geçersiz")
    wallets = feed.get("wallets")
    events = feed.get("events")
    if not isinstance(wallets, list) or not isinstance(events, list):
        return _snapshot(previous, now, "INVALID", "Cüzdan/işlem dizileri eksik")
    if len(wallets) > 500 or len(events) > 5000:
        return _snapshot(previous, now, "INVALID", "Veri hacmi sınırı aşıldı")
    selected = {}
    for entry in wallets:
        if not isinstance(entry, dict):
            continue
        chain, address = entry.get("chain"), entry.get("address")
        profit, rate = (_number(entry.get("profit30dUsd")),
                        _number(entry.get("winRate30dPct")))
        checked = _date(entry.get("performanceAsOf"))
        owner = entry.get("ownerGroup")
        if (chain not in ("solana", "base") or not _address(chain, address)
                or profit is None or profit <= 750_000
                or rate is None or not 65 <= rate <= 100
                or checked is None or not dt.timedelta(0) <= now-checked <= STATS_MAX_AGE
                or entry.get("performanceVerified") is not True
                or entry.get("independenceVerified") is not True
                or not isinstance(owner, str) or not owner.strip()):
            continue
        key = (chain, address.lower())
        selected[key] = {**entry, "_profit": profit}
    # Even a provider reporting more wallets can influence at most top 15.
    selected = dict(sorted(selected.items(), key=lambda item:
                           item[1]["_profit"], reverse=True)[:MAX_WALLETS])
    valid = []
    seen_tx = set()
    for event in events:
        if not isinstance(event, dict):
            continue
        key = (event.get("chain"), str(event.get("wallet", "")).lower())
        if key not in selected:
            continue
        verified = _event(event, key[0], key[1], now)
        if verified is None:
            continue
        tx_key = (key[0], verified["txHash"].lower())
        if tx_key in seen_tx:
            continue
        seen_tx.add(tx_key)
        verified["_owner"] = selected[key]["ownerGroup"]
        valid.append(verified)
    state = _snapshot(previous, now, "READY",
                      "Kaynak bildirimi kontrol edildi; zincir üstü iddialar sağlayıcıya aittir",
                      walletCount=len(selected), eventCount=len(valid),
                      sourceAsOf=_stamp(as_of))
    buys = {}
    sells = {}
    for row in valid:
        key = f'{row["_chain"]}:{row["_token"]}'
        if now - WINDOW <= row["_at"] <= now:
            (buys if row["side"] == "BUY" else sells).setdefault(key, []).append(row)
    for key, matches in sorted(buys.items()):
        if key in state["seenTokens"]:
            continue
        matches.sort(key=lambda e: e["_at"])
        # Require three different wallets, beneficial owners AND funding origins.
        unique = []
        owners, funding, wallets_seen = set(), set(), set()
        for row in matches:
            w, o, f = row["_wallet"], row["_owner"], row["fundingGroup"]
            if w in wallets_seen or o in owners or f in funding:
                continue
            unique.append(row)
            wallets_seen.add(w)
            owners.add(o)
            funding.add(f)
        if len(unique) < 3 or unique[-1]["_at"]-unique[0]["_at"] > WINDOW:
            continue
        row = unique[-1]
        signal = {
            "type": "BUY_CLUSTER", "at": _stamp(now), "chain": row["_chain"],
            "tokenAddress": row["_token"], "symbol": row["symbol"],
            "walletCount": len(unique), "windowMinutes": 20,
            "liquidityUsd": row["safety"]["liquidityUsd"],
            "txHashes": [x["txHash"] for x in unique],
            "wallets": [x["_wallet"] for x in unique],
            "status": "REVIEW_ONLY", "automaticOrder": False,
        }
        state["newSignals"].append(signal)
        state["history"].append(signal)
        state["seenTokens"][key] = _stamp(now)
    for key, matches in sorted(sells.items()):
        if key not in state["seenTokens"]:
            continue
        for row in matches:
            txkey = f'{key}:{row["txHash"].lower()}'
            if txkey in state["seenSales"]:
                continue
            sale = {
                "type": "SMART_WALLET_SELL", "at": _stamp(now),
                "chain": row["_chain"], "tokenAddress": row["_token"],
                "symbol": row["symbol"], "wallet": row["_wallet"],
                "txHash": row["txHash"], "status": "REVIEW_ONLY",
                "automaticOrder": False,
            }
            state["saleAlerts"].append(sale)
            state["history"].append(sale)
            state["seenSales"][txkey] = _stamp(now)
    state["history"] = state["history"][-80:]
    # Limit sales dedupe storage to the last 24h, but never erase token entry history.
    state["seenSales"] = {k: v for k, v in state["seenSales"].items()
                          if _date(v) and now - HISTORY <= _date(v) <= now}
    return state


def refresh(previous, now=None, *, feed_url=None, opener=None):
    now = (now or dt.datetime.now(UTC)).astimezone(UTC)
    url = feed_url if feed_url is not None else os.getenv("SMART_WALLET_FEED_URL", "")
    if not url:
        return _snapshot(previous, now, "NOT_CONFIGURED",
                         "Güvenilir cüzdan veri kaynağı bağlı değil; sinyal üretilemez")
    try:
        feed = read_feed(url, opener=opener)
        return evaluate(feed, previous, now)
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError) as exc:
        return _snapshot(previous, now, "UNAVAILABLE",
                         f"Akıllı cüzdan sağlayıcısı okunamadı: {type(exc).__name__}")
