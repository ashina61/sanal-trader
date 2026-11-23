"""Bounded parallel fetching of independent, public candle endpoints.

The scanner itself never submits orders. Worker threads read independent public
REST URLs only; selection, wallet accounting and decision-making remain on the
single main thread. No fabricated fallback bars on missing/invalid responses.
"""
from concurrent.futures import ThreadPoolExecutor
import time

DEFAULT_WORKERS = 6
MAX_WORKERS = 8


def fetch_candle_batch(provider, symbols, parser, minimum, workers=DEFAULT_WORKERS):
    """Fetch independent symbols concurrently, preserving deterministic order.

    provider(symbol) -> public candle payload.
    parser(payload) -> verified, closed, time-ordered price list.
    Every symbol is attempted once; invalid/failing data is omitted. An empty
    batch requires zero threads. Do not pass a mutable wallet or order callback.
    """
    names = sorted(set(symbols))
    if not names:
        return {}, {"requested": 0, "valid": 0, "failed": 0, "elapsedSec": 0.0}
    if not isinstance(workers, int) or not 1 <= workers <= MAX_WORKERS:
        raise ValueError("Unsafe candle worker count")

    def read(symbol):
        try:
            closes = parser(provider(symbol))
            if len(closes) >= minimum:
                return closes
        except Exception:
            pass
        return None

    begin = time.perf_counter()
    with ThreadPoolExecutor(max_workers=min(workers, len(names))) as pool:
        batches = list(pool.map(read, names))
    good = {name: prices for name, prices in zip(names, batches)
            if prices is not None}
    return good, {
        "requested": len(names),
        "valid": len(good),
        "failed": len(names) - len(good),
        "elapsedSec": round(time.perf_counter() - begin, 3),
    }
