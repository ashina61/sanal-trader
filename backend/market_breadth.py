"""Descriptive market breadth from observed current 24h public tickers.

No extra API calls, financial predictions, or synthetic prices.
"""
import math
import statistics


def market_breadth(quotes):
    moves = []
    for pair, item in quotes.items():
        value = item.get("change24h") if isinstance(item, dict) else None
        if (isinstance(value, (int, float)) and math.isfinite(value)
                and -100 <= value <= 10_000):
            moves.append((pair, float(value)))
    up = sum(1 for _, x in moves if x > .1)
    down = sum(1 for _, x in moves if x < -.1)
    flat = len(moves) - up - down
    sorted_moves = sorted(moves, key=lambda v: v[1])
    return {
        "tracked": len(moves), "up": up, "down": down, "flat": flat,
        "advancersPct": round(100 * up / len(moves), 1) if moves else None,
        "medianChange24hPct": round(statistics.median(x for _, x in moves), 3)
        if moves else None,
        "leaders": [{"symbol": s, "change24hPct": round(x, 2)}
                    for s, x in reversed(sorted_moves[-3:])],
        "laggards": [{"symbol": s, "change24hPct": round(x, 2)}
                     for s, x in sorted_moves[:3]],
    }
