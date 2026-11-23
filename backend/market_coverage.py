"""Broad liquid universe, bounded chart batches, and observed coverage counts."""
import datetime as dt

MIN_VOLUME_USDT = 1_000_000
HOURLY_BATCH = 72
FAST_BATCH = 96
MINUTE_BATCH = 96
RECENT_SECONDS = 600


def parse_time(value):
    try:
        when = dt.datetime.fromisoformat(str(value).replace('Z', '+00:00'))
        return when if when.tzinfo else None
    except (ValueError, TypeError):
        return None


def iso(t):
    return t.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def minute_focus(eligible, available, held, core, cursor=0):
    """Prioritize held/core/leaders, then rotate fairly through the rest.

    This only chooses data reads. It cannot place orders, relax liquidity
    requirements or use incomplete minute confirmation for a new entry.
    """
    universe = {row['symbol'] for row in eligible}
    held = set(held) & set(available)
    volume = sorted(eligible, key=lambda row: (-row['volume'], row['symbol']))
    priority = list(sorted(held)) + [p for p in core if p in available]
    priority += [row['symbol'] for row in volume[:36]]
    priority += [row['symbol'] for row in sorted(eligible,
        key=lambda row: (-row['change'], row['symbol']))[:10]]
    priority += [row['symbol'] for row in sorted(eligible,
        key=lambda row: (row['change'], row['symbol']))[:10]]
    priority = list(dict.fromkeys(p for p in priority if p in available))
    limit = max(MINUTE_BATCH, len(held))
    priority = priority[:limit]
    rotating = sorted(universe - set(priority))
    cursor = cursor if isinstance(cursor, int) and cursor >= 0 else 0
    start = cursor % len(rotating) if rotating else 0
    take = min(limit - len(priority), len(rotating))
    chosen = [rotating[(start + i) % len(rotating)] for i in range(take)]
    return set(priority + chosen), {
        'limit': limit, 'priorityPairs': len(priority),
        'rotatingPairs': len(rotating), 'rotationReadPairs': len(chosen),
        'nextCursor': (start + take) % len(rotating) if rotating else 0,
    }


def due_batch(symbols, cache, t, refresh_seconds, limit, held=()):
    due = []
    held = set(held)
    for symbol in symbols:
        fetched = parse_time(cache.get(symbol, {}).get('fetchedAt'))
        if fetched is None or fetched > t or (t - fetched).total_seconds() >= refresh_seconds:
            due.append((symbol not in held, fetched.timestamp() if fetched else 0, symbol))
    due.sort()
    # Never exclude a held position just because many new symbols need warmup.
    size = max(limit, sum(symbol in held for _, _, symbol in due))
    return [symbol for _, _, symbol in due[:size]]


def snapshot(state, lookup, eligible, latest, minute_bars, focus, policy, t, plain_usdt_count):
    universe = {row['symbol'] for row in eligible}
    seen = state.setdefault('minuteSeenAt', {})
    for symbol in list(seen):
        if symbol not in universe:
            seen.pop(symbol)
    for symbol in set(minute_bars) & universe:
        seen[symbol] = iso(t)
    recent = sum(1 for symbol in universe if
        (when := parse_time(seen.get(symbol))) is not None
        and 0 <= (t - when).total_seconds() <= RECENT_SECONDS)

    def valid(book, symbol, minimum, max_age):
        row = state.get(book, {}).get(symbol, {})
        fetched = parse_time(row.get('fetchedAt'))
        return (fetched is not None and 0 <= (t - fetched).total_seconds() <= max_age
                and len(row.get('prices', [])) >= minimum)

    ready = [symbol for symbol in universe if
        valid('histories', symbol, 60, 7200)
        and valid('intraday', symbol, 20, 1500)
        and valid('micro', symbol, 35, 420)]
    return {
        'schema': 1, 'at': iso(t), 'freshMarketPairs': len(lookup),
        'plainUsdtPairs': plain_usdt_count, 'liquidPairs': len(universe),
        'excludedLowVolumePairs': plain_usdt_count - len(universe),
        'minQuoteVolumeUsdt': MIN_VOLUME_USDT,
        'quoteCheckedPairs': len(set(latest) & universe),
        'minuteRequestedPairs': len(set(focus) & universe),
        'minuteRequestedTotalPairs': len(focus),
        'minuteObservedPairs': len(set(minute_bars) & universe),
        'fullTechnicalPairs': len(ready), 'recentMinutePairs': recent,
        'recentWindowMinutes': RECENT_SECONDS // 60,
        'rotationPendingPairs': len(universe - set(focus)),
        'hourlyCachedPairs': sum(valid('histories', s, 60, 7200) for s in universe),
        'fastCachedPairs': sum(valid('intraday', s, 20, 1500) for s in universe),
        'liquidSymbols': sorted(universe), 'minuteSymbols': sorted(set(minute_bars) & universe),
        'focusPolicy': policy,
    }
