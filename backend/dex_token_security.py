"""Read-only DEX contract risk research from GoPlus public token-security API.

Never a safety certification, honeypot-proof simulation or trading permission.
Unrecognized or missing fields are UNKNOWN, not safe. No API key is required
by the public endpoint at the documented free tier; availability is best effort.
This module does NOT send transactions or change the paper wallet.
"""
import json
import math
import urllib.error
import urllib.parse
import urllib.request

from backend.smart_money import _address

BASE_CHAIN = "8453"
HOST = "https://api.gopluslabs.io"
MAX_BYTES = 600_000
MAX_TOKENS = 4

# Danger states are only recognized on literal 0/1 or false/true; a missing
# or ambiguous string never turns into an assurance.
EVM_FLAGS = (
    ("is_honeypot", "Olası honeypot"),
    ("is_mintable", "Yeni token basma yetkisi"),
    ("is_blacklisted", "Kara liste mekanizması"),
    ("transfer_pausable", "Transfer durdurma"),
    ("can_take_back_ownership", "Sahipliği geri alma"),
    ("hidden_owner", "Gizli sahip yetkisi"),
    ("slippage_modifiable", "Vergi/kayma değiştirme"),
    ("is_proxy", "Yükseltilebilir sözleşme"),
)
SOLANA_FLAGS = (
    ("mintable", "Token basım yetkisi"),
    ("freezable", "Hesap dondurma yetkisi"),
    ("closable", "Hesap kapatma yetkisi"),
    ("default_account_state", "Kısıtlı varsayılan hesap"),  # diagnostic only
)


def _flag(value):
    if isinstance(value, bool):
        return value
    if value in (0, 1, "0", "1"):
        return str(value) == "1"
    return None


def _number(value):
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
        return number if math.isfinite(number) and number >= 0 else None
    except (ValueError, TypeError, OverflowError):
        return None


def _url(chain, token):
    if chain not in ("base", "solana") or not _address(chain, token):
        raise ValueError("Unsupported network or invalid token address")
    path = ("/api/v1/token_security/" + BASE_CHAIN if chain == "base"
            else "/api/v1/solana/token_security")
    query = urllib.parse.urlencode({"contract_addresses": token})
    return HOST + path + "?" + query


def _fetch(chain, token, *, opener=None):
    url = _url(chain, token)
    req = urllib.request.Request(url, headers={
        "Accept": "application/json", "User-Agent": "SanalTraderRiskResearch/1.0"
    })
    source = opener or urllib.request.urlopen
    with source(req, timeout=6) as response:
        body = response.read(MAX_BYTES + 1)
    if len(body) > MAX_BYTES:
        raise ValueError("Security provider response too large")
    response = json.loads(body)
    if not isinstance(response, dict) or str(response.get("code")) != "1":
        raise ValueError("Security provider unavailable or rejected request")
    results = response.get("result")
    if not isinstance(results, dict):
        raise ValueError("Security results missing")
    return results


def _result_for(chain, token, result):
    if not isinstance(result, dict):
        return None
    if chain == "base":
        return next((v for k, v in result.items()
                     if isinstance(k, str) and k.lower() == token.lower()
                     and isinstance(v, dict)), None)
    return next((v for k, v in result.items()
                 if k == token and isinstance(v, dict)), None)


def review(chain, token, response):
    """Only describe known warning flags. Never call any token 'safe'."""
    data = _result_for(chain, token, response)
    if data is None:
        return {"status": "UNKNOWN", "reason": "Sağlayıcı token kaydı döndürmedi",
                "flags": [], "knownChecks": 0, "tokenSafetyVerified": False,
                "tradingAllowed": False}
    flags, checked = [], 0
    spec = EVM_FLAGS if chain == "base" else SOLANA_FLAGS
    for key, label in spec:
        if key == "default_account_state":
            continue  # non-boolean enum; cannot classify without schema
        state = _flag(data.get(key))
        if state is None:
            continue
        checked += 1
        if state:
            flags.append(label)
    if chain == "base":
        for name in ("buy_tax", "sell_tax"):
            amount = _number(data.get(name))
            if amount is None:
                continue
            checked += 1
            if amount > .05:
                flags.append(("Alış" if name == "buy_tax" else "Satış") +
                             f" vergisi yüksek (%{amount * 100:.1f})")
        if _flag(data.get("is_open_source")) is False:
            flags.append("Kaynak kod doğrulanmamış")
    else:
        # Solana's API may expose explicit mint/freeze authority strings.
        # Their exact meanings vary by token program; don't mark safe.
        for key, label in (("mint_authority", "Mint yetkisi mevcut"),
                           ("freeze_authority", "Freeze yetkisi mevcut")):
            value = data.get(key)
            if isinstance(value, str) and value and value != "null":
                flags.append(label)
    status = "RISK_FLAGGED" if flags else "PARTIAL" if checked else "UNKNOWN"
    reason = ("Potansiyel sözleşme riski bulundu" if flags
              else "Bazı kontrollerde uyarı yok; LP kilidi, sözleşme ve satış "
                   "gerçekleşmesi tamamen doğrulanmadı" if checked
              else "Anlaşılabilir güvenlik alanı gelmedi")
    return {
        "status": status, "reason": reason, "flags": flags[:10],
        "knownChecks": checked, "tokenSafetyVerified": False,
        "tradingAllowed": False,
    }


def inspect(pools, *, fetcher=None):
    """Inspect at most four already-selected DEX pools; read-only."""
    provider = fetcher or _fetch
    records = []
    seen = set()
    for pool in pools:
        if len(records) >= MAX_TOKENS or not isinstance(pool, dict):
            break
        chain, token = pool.get("chain"), pool.get("token")
        if not isinstance(chain, str) or not isinstance(token, str):
            continue
        if (chain, token) in seen or not _address(chain, token):
            continue
        seen.add((chain, token))
        item = {"chain": chain, "tokenAddress": token,
                "symbol": str(pool.get("symbol", "—"))[:24],
                "pool": pool.get("pool"),
                "source": "GoPlus public Token Security",
                "tokenSafetyVerified": False, "tradingAllowed": False}
        try:
            checked = review(chain, token, provider(chain, token))
            item.update(checked)
        except (OSError, ValueError, UnicodeError, KeyError, TypeError) as exc:
            error = (f"HTTP_{exc.code}" if isinstance(exc, urllib.error.HTTPError)
                     else type(exc).__name__)
            item.update({"status": "UNAVAILABLE",
                         "reason": "Sözleşme riski kontrol edilemedi: " + error,
                         "flags": [], "knownChecks": 0})
        records.append(item)
    return {
        "status": "RESEARCH_ONLY",
        "source": "GoPlus public Token Security",
        "results": records, "checked": len(records),
        "riskFlagged": sum(x["status"] == "RISK_FLAGGED" for x in records),
        "unknown": sum(x["status"] in ("UNAVAILABLE", "UNKNOWN")
                       for x in records),
        "automaticOrder": False, "tokenSafetyVerified": False,
    }
