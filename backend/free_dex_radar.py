"""Free public DEX trade discovery (NOT a qualified profitable-wallet strategy).

Samples a few Solana/Base GeckoTerminal trending pools, observes real
reported transaction senders, and reports *unverified* three-sender clusters.
No paid API, sign-up, simulated fills, or exchange orders. Provider data may
be incomplete, delayed or unavailable; no ROI, owner independence, fresh
funding, LP locks or mint safety are inferred from a public trade tape.
"""
import datetime as dt
import json
import math
import time
import urllib.error
import urllib.request
from collections import defaultdict

from backend.smart_money import _address, _date, _number, _stamp
from backend.dex_token_security import inspect as inspect_token_security

UTC = dt.timezone.utc
ORIGIN = "https://api.geckoterminal.com/api/v2"
CHAINS = ("solana", "base")
INTERVAL = dt.timedelta(minutes=12)
WINDOW = dt.timedelta(minutes=20)
HISTORY = dt.timedelta(hours=24)
POOLS_PER_CHAIN = 2
MIN_POOL_USD = 200_000
MIN_TRADE_USD = 100
# Shared public API: keep below 10 requests/minute on a dedicated runner.
PUBLIC_REQUEST_GAP_SECONDS = 6
MAX_BYTES = 1_500_000
STABLE_SYMBOLS = {"SOL", "WSOL", "USDC", "USDT", "WETH", "ETH", "WBTC",
                  "BTC", "DAI", "USDE", "CBBTC", "FDUSD"}


def _error_label(exc):
    if isinstance(exc, urllib.error.HTTPError):
        return f"HTTP_{exc.code}"
    return type(exc).__name__


def _initial(now, status, reason):
    return {
        "status": status,
        "source": "GeckoTerminal public API",
        "mode": "UNVERIFIED_DEX_OBSERVATION",
        "checkedAt": _stamp(now),
        "reason": reason,
        "networks": ["solana", "base"],
        "poolsScreened": 0,
        "tradesChecked": 0,
        "observedSenders": 0,
        "walletsObserved": [],
        "newClusters": [],
        "history": [],
        "errors": [],
        "notSmartWalletProof": True,
        "automaticOrder": False,
    }


def _request(path, *, opener=None):
    # Only whitelisted, internally constructed GeckoTerminal paths.
    if not (path.startswith("/networks/solana/") or
            path.startswith("/networks/base/")):
        raise ValueError("Invalid free data source path")
    req = urllib.request.Request(ORIGIN + path, headers={
        "Accept": "application/json",
        "User-Agent": "SanalTraderResearch/1.0",
    })
    source = opener or urllib.request.urlopen
    with source(req, timeout=8) as response:
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError("Public DEX reply too large")
    obj = json.loads(body.decode("utf-8"))
    if not isinstance(obj, dict) or not isinstance(obj.get("data"), list):
        raise ValueError("Invalid public DEX JSON response")
    return obj


def _select_pools(response, chain):
    """Only clearly identified token+pool; no guessed token from pool name."""
    chosen = []
    for item in response.get("data", [])[:35]:
        if not isinstance(item, dict):
            continue
        attrs = item.get("attributes")
        relationships = item.get("relationships")
        if not isinstance(attrs, dict) or not isinstance(relationships, dict):
            continue
        pool = attrs.get("address")
        token_rel = relationships.get("base_token")
        token_id = (token_rel.get("data") or {}).get("id") if isinstance(token_rel, dict) else None
        prefix = chain + "_"
        token = token_id[len(prefix):] if isinstance(token_id, str) and token_id.startswith(prefix) else None
        liquidity = _number(attrs.get("reserve_in_usd"))
        price_change = attrs.get("price_change_percentage")
        hour_change = _number(price_change.get("h1")) if isinstance(price_change, dict) else None
        name = attrs.get("name", "")
        symbol = name.split(" / ")[0].strip() if isinstance(name, str) else ""
        # h1 price movement is required: no cherry picking on missing data.
        if (not _address(chain, pool) or not _address(chain, token)
                or liquidity is None or liquidity < MIN_POOL_USD
                or hour_change is None or hour_change > 30
                or not 1 <= len(symbol) <= 24
                or symbol.upper() in STABLE_SYMBOLS):
            continue
        chosen.append({
            "chain": chain, "pool": pool, "token": token,
            "symbol": symbol, "liquidityUsd": round(liquidity, 2),
            "priceChange1hPct": round(hour_change, 3),
        })
    chosen.sort(key=lambda row: row["liquidityUsd"], reverse=True)
    return chosen[:POOLS_PER_CHAIN]


def _trade_rows(response, pool, now):
    rows = []
    chain = pool["chain"]
    for item in response.get("data", [])[:300]:
        if not isinstance(item, dict):
            continue
        a = item.get("attributes")
        if not isinstance(a, dict) or a.get("is_anomalous") is True:
            continue
        sender, txid = a.get("tx_from_address"), a.get("tx_hash")
        at = _date(a.get("block_timestamp"))
        volume = _number(a.get("volume_in_usd"))
        side = a.get("kind")
        if (not _address(chain, sender) or not _address(chain, txid, tx=True)
                or at is None or not now - WINDOW <= at <= now
                or volume is None or volume < MIN_TRADE_USD
                or side not in ("buy", "sell")):
            continue
        rows.append({
            "chain": chain, "tokenAddress": pool["token"],
            "symbol": pool["symbol"], "pool": pool["pool"],
            "sender": sender.lower() if chain == "base" else sender,
            "txHash": txid.lower() if chain == "base" else txid,
            "side": side.upper(), "at": _stamp(at),
            "volumeUsd": round(volume, 2),
            "liquidityUsd": pool["liquidityUsd"],
        })
    return rows


def _history(previous, now):
    raw = previous.get("history", []) if isinstance(previous, dict) else []
    return [row for row in raw[-100:] if isinstance(row, dict)
            and _date(row.get("at")) and
            now - HISTORY <= _date(row["at"]) <= now]


def analyze_batches(batches, previous=None, now=None, errors=None):
    """Pure analysis of public pool/trade responses for deterministic tests."""
    now = (now or dt.datetime.now(UTC)).astimezone(UTC)
    history = _history(previous, now)
    errors = list(errors or [])
    current = _initial(now, "OBSERVING",
                       "Herkese açık DEX işlemleri; kârlı cüzdan doğrulaması yok")
    current["errors"] = errors[:8]
    by_tx = set()
    observed = []
    sampled = set()
    for pool, trades in batches:
        sampled.add((pool["chain"], pool["pool"]))
        for row in _trade_rows(trades, pool, now):
            key = (row["chain"], row["txHash"])
            if key in by_tx:
                continue
            by_tx.add(key)
            observed.append(row)
    current["poolsScreened"] = len(sampled)
    current["tradesChecked"] = len(observed)
    rankings = defaultdict(lambda: {"buys": 0, "sells": 0, "volume": 0.0})
    by_token = defaultdict(list)
    for row in observed:
        key = (row["chain"], row["sender"])
        rankings[key]["buys" if row["side"] == "BUY" else "sells"] += 1
        rankings[key]["volume"] += row["volumeUsd"]
        by_token[(row["chain"], row["tokenAddress"].lower())].append(row)
    current["observedSenders"] = len(rankings)
    ranked = sorted(rankings.items(),
                    key=lambda x: (x[1]["buys"], x[1]["volume"]), reverse=True)
    current["walletsObserved"] = [
        {"chain": k[0], "address": k[1], "observedBuys": v["buys"],
         "observedSells": v["sells"], "sampledVolumeUsd": round(v["volume"], 2),
         "verified30dProfit": False}
        for k, v in ranked[:15]
    ]
    recently = {(r.get("chain"), str(r.get("tokenAddress", "")).lower())
                for r in history if r.get("type") == "THREE_SENDERS_UNVERIFIED"}
    for (chain, token), token_rows in sorted(by_token.items()):
        buys = sorted((r for r in token_rows if r["side"] == "BUY"),
                      key=lambda r: r["at"])
        unique = []
        senders = set()
        for row in buys:
            if row["sender"] in senders:
                continue
            senders.add(row["sender"])
            unique.append(row)
        if len(unique) < 3 or (chain, token) in recently:
            continue
        # Even different transaction senders may represent the SAME OWNER;
        # never mark them independent smart wallets.
        cluster = {
            "type": "THREE_SENDERS_UNVERIFIED", "status": "RESEARCH_ONLY",
            "at": _stamp(now), "chain": chain, "tokenAddress": token,
            "symbol": unique[0]["symbol"], "senderCount": len(unique),
            "poolCount": len({r["pool"] for r in unique}),
            "sampledBuyVolumeUsd": round(sum(r["volumeUsd"] for r in unique), 2),
            "wallets": [r["sender"] for r in unique[:15]],
            "txHashes": [r["txHash"] for r in unique[:15]],
            "profitableWalletsVerified": False,
            "independenceVerified": False,
            "freshFundsVerified": False, "tokenSafetyVerified": False,
            "automaticOrder": False,
        }
        current["newClusters"].append(cluster)
        history.append(cluster)
    current["history"] = history[-100:]
    if errors:
        current["status"] = "DEGRADED" if batches else "UNAVAILABLE"
        current["reason"] = ("Bazı DEX kaynaklarına ulaşılamadı; kapsam eksik"
                             if batches else "Ücretsiz DEX kaynakları erişilemiyor")
    return current


def refresh(previous=None, now=None, *, fetcher=None, sleep=None):
    """Rate-limited public read; never touches the simulated portfolio."""
    now = (now or dt.datetime.now(UTC)).astimezone(UTC)
    prev = previous if isinstance(previous, dict) else {}
    last = _date(prev.get("checkedAt"))
    if (last and dt.timedelta(0) <= now - last < INTERVAL
            and prev.get("status") in ("OBSERVING", "DEGRADED", "UNAVAILABLE")):
        return prev
    fetch = fetcher or _request
    delay = sleep if sleep is not None else time.sleep
    batches, errors = [], []
    calls = 0
    for chain in CHAINS:
        try:
            # Do not hammer free shared infrastructure.
            if calls:
                delay(PUBLIC_REQUEST_GAP_SECONDS)
            pools_response = fetch(f"/networks/{chain}/trending_pools")
            calls += 1
            pools = _select_pools(pools_response, chain)
            for pool in pools:
                try:
                    delay(PUBLIC_REQUEST_GAP_SECONDS)
                    calls += 1
                    trades = fetch(
                        f"/networks/{chain}/pools/{pool['pool']}/trades")
                    batches.append((pool, trades))
                except (ValueError, OSError, UnicodeError, KeyError) as exc:
                    errors.append(f"{chain}:trades:{_error_label(exc)}")
        except (ValueError, OSError, UnicodeError, KeyError) as exc:
            errors.append(f"{chain}:pools:{_error_label(exc)}")
    state = analyze_batches(batches, prev, now, errors)
    # No valid pools != provider outage; distinguish lack of matches.
    if not batches and not errors:
        state["status"] = "OBSERVING"
        state["reason"] = "Ücretsiz havuz taramasında filtreye uygun havuz yok"
    # Read-only GoPlus token contract diagnostics: only already-observed
    # pools. Never upgrades an on-chain cluster to verified profitable wallets.
    unique_pools = list({(p["chain"], p["token"]): p
                         for p, _ in batches}.values())
    try:
        state["tokenRisk"] = inspect_token_security(unique_pools)
    except Exception as exc:
        state["tokenRisk"] = {
            "status": "UNAVAILABLE", "checked": 0, "results": [],
            "riskFlagged": 0, "unknown": 0,
            "reason": "GoPlus gözlemi alınamadı: " + type(exc).__name__,
            "automaticOrder": False, "tokenSafetyVerified": False,
        }
    state["requestsMade"] = calls
    return state
