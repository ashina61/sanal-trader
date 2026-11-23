"""Free, read-only crypto headline radar.

RSS titles are UNTRUSTED external data: never run commands, follow article URLs,
or pass headlines as instructions to an LLM. News only restricts NEW paper
entries, never opens an order or forces an exit.
"""
import datetime as dt
import email.utils
import re
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

FEEDS = (
    ("CoinDesk", "https://www.coindesk.com/arc/outboundfeeds/rss/"),
    ("Cointelegraph", "https://cointelegraph.com/rss"),
)
FEED_DOMAINS = {
    "CoinDesk": "www.coindesk.com",
    "Cointelegraph": "cointelegraph.com",
}
HEADLINE_AGE_SECONDS = 6 * 3600
ALERT_AGE_SECONDS = 2 * 3600
REFRESH_INTERVAL_SECONDS = 20 * 60
KEYWORDS = {
    "hack": ("hack", "hacked", "exploit", "drained", "breach"),
    "delisting": ("delist", "delisting", "removed from trading"),
    "insolvency": ("insolvency", "bankruptcy", "withdrawals halted", "bank run"),
    "regulatory": ("sec charges", "regulatory crackdown", "trading ban"),
    "depeg": ("depeg", "de-pegged", "lost its peg"),
}
# Restrict ticker aliases to names that are not common English words.
COIN_ALIASES = {
    "BTCUSDT": ("bitcoin", "btc"),
    "ETHUSDT": ("ethereum", "ether", "eth"),
    "SOLUSDT": ("solana", "sol"),
    "XRPUSDT": ("ripple", "xrp"),
    "BNBUSDT": ("binance coin", "bnb"),
    "DOGEUSDT": ("dogecoin", "doge"),
    "ADAUSDT": ("cardano", "ada"),
    "AVAXUSDT": ("avalanche", "avax"),
    "LINKUSDT": ("chainlink",),
    "LTCUSDT": ("litecoin", "ltc"),
    "DOTUSDT": ("polkadot",),
    "UNIUSDT": ("uniswap",),
    "NEARUSDT": ("near protocol",),
    "PYTHUSDT": ("pyth network",),
    "WLDUSDT": ("worldcoin", "world id"),
}
BROAD_SHOCK = ("crypto exchange", "cryptocurrency exchange", "stablecoin",
               "crypto market", "bitcoin market")


def _clean(text):
    return re.sub(r"\s+", " ", str(text or "")).strip()[:200]


def _parse_date(value):
    try:
        t = email.utils.parsedate_to_datetime(value)
        if t.tzinfo is None:
            return None
        return t.astimezone(dt.timezone.utc)
    except (ValueError, TypeError, IndexError, OverflowError):
        return None


def classify(title):
    text = title.casefold()
    categories = [kind for kind, words in KEYWORDS.items()
                  if any(re.search(r"(?<!\w)" + re.escape(w) + r"(?!\w)", text)
                         for w in words)]
    targeted = []
    for pair, aliases in COIN_ALIASES.items():
        if any(re.search(r"(?<!\w)" + re.escape(w) + r"(?!\w)", text)
               for w in aliases):
            targeted.append(pair)
    broad = bool(categories and any(w in text for w in BROAD_SHOCK))
    return categories, targeted, broad


def parse_rss(xml_bytes, source, now):
    """Parse only current published articles, discarding suspicious metadata."""
    if not isinstance(xml_bytes, bytes) or len(xml_bytes) > 300_000:
        raise ValueError("Invalid/oversized news feed")
    root = ET.fromstring(xml_bytes)
    items = []
    for item in root.findall(".//item")[:40]:
        title = _clean(item.findtext("title"))
        pub = _parse_date(item.findtext("pubDate"))
        raw_url = _clean(item.findtext("link"))
        host = (urlparse(raw_url).hostname or "").lower()
        if (not title or pub is None or not raw_url.startswith("https://")
                or host != FEED_DOMAINS[source]):
            continue
        age = (now - pub).total_seconds()
        if not (0 <= age <= HEADLINE_AGE_SECONDS):
            continue
        categories, symbols, broad = classify(title)
        items.append({
            "title": title, "source": source, "url": raw_url,
            "publishedAt": pub.isoformat().replace("+00:00", "Z"),
            "categories": categories, "symbols": symbols, "broad": broad,
        })
    return items


def fetch_rss(now, opener=None):
    opener = opener or urllib.request.urlopen
    collected, failures = [], []
    for name, url in FEEDS:
        try:
            request = urllib.request.Request(url, headers={
                "User-Agent": "SanalTraderResearch/1.0",
                "Accept": "application/rss+xml, application/xml, text/xml",
            })
            with opener(request, timeout=6) as response:
                content = response.read(300_001)
            collected.extend(parse_rss(content, name, now))
        except (Exception) as exc:
            # No credentials or raw remote responses in public wallet logs.
            failures.append(name + ": " + type(exc).__name__)
    return collected, failures


def news_snapshot(articles, now, failures=None):
    fresh = []
    seen = set()
    for row in articles:
        when = _parse_iso(row.get("publishedAt"))
        if when is None or not (0 <= (now - when).total_seconds() <= HEADLINE_AGE_SECONDS):
            continue
        key = (row.get("source"), row.get("title"))
        if key in seen:
            continue
        seen.add(key)
        fresh.append(row)
    fresh.sort(key=lambda a: a["publishedAt"], reverse=True)
    return {
        "checkedAt": now.isoformat().replace("+00:00", "Z"),
        "status": ("OK" if fresh else "UNAVAILABLE" if failures else "EMPTY"),
        "sourceCount": len({a["source"] for a in fresh}),
        "failures": (failures or [])[:2],
        "headlines": fresh[:20],
    }


def _parse_iso(value):
    try:
        when = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return when.astimezone(dt.timezone.utc) if when.tzinfo else None
    except (ValueError, TypeError):
        return None


def entry_alert(snapshot, pair, now):
    """Return verifiable relevant recent warnings, or empty list.

    General market news is informational unless 2 independent outlets report a
    similar broad shock. Coin-specific critical headlines block only that coin's
    NEW entry; they NEVER issue a SELL or start a SHORT.
    """
    checked = _parse_iso(snapshot.get("checkedAt")) if isinstance(snapshot, dict) else None
    if checked is None or (now - checked).total_seconds() > REFRESH_INTERVAL_SECONDS * 2:
        return []
    headlines = snapshot.get("headlines", [])
    direct, broad_sources = [], set()
    for item in headlines if isinstance(headlines, list) else []:
        published = _parse_iso(item.get("publishedAt")) if isinstance(item, dict) else None
        if published is None or not (0 <= (now - published).total_seconds() <= ALERT_AGE_SECONDS):
            continue
        if not item.get("categories"):
            continue
        if pair in item.get("symbols", []):
            direct.append(item)
        if item.get("broad"):
            broad_sources.add(item.get("source"))
    if direct:
        return direct[:3]
    if len(broad_sources) >= 2:
        return [x for x in headlines if x.get("broad") and x.get("categories")][:3]
    return []
