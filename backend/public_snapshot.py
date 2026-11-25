"""Small, read-only public dashboard view of the ONE paper wallet.

The full bot-data/state.json remains the canonical, unmodified account
ledger and observation tape. The mobile/web UI does not require the large
OHLC caches, raw forward evidence or 288 full-cycle debug records on every
refresh. Never overwrite the canonical wallet with this display snapshot.
"""
import argparse
import json
from pathlib import Path

DISPLAY_FIELDS = (
    "schema", "source", "enabled", "mode",
    "initialCashTry", "cashTry", "equityTry", "netLiquidationTry",
    "realizedTry", "paidFeesTry", "holdings", "shorts", "marksTry",
    "directionStats", "performance", "objective", "tradeLearning",
    "tracked", "screened", "cycles",
    "lastRunAt", "lastSuccessAt", "lastError", "lastDecision",
    "lastTriggerAt", "lastTriggerEvent", "lastScheduledTriggerAt",
    "runtimeStatus", "coverageStats", "decisionPlan", "trades",
    "equityHistory", "smartMoney", "freeDexRadar", "publicApiHealth",
    "newsPulse", "signalStats",
)

REQUIRED = ("schema", "initialCashTry", "cashTry", "equityTry",
            "holdings", "trades", "lastSuccessAt")


def view(wallet):
    if not isinstance(wallet, dict) or any(k not in wallet for k in REQUIRED):
        raise ValueError("Incomplete canonical virtual wallet, no public snapshot")
    if wallet.get("schema") != 1:
        raise ValueError("Unsupported canonical wallet schema")
    if not isinstance(wallet["holdings"], dict) or not isinstance(wallet["trades"], list):
        raise ValueError("Invalid wallet holdings or trading history")
    # Keep ALL observed virtual trades and full net equity curve. Only the
    # redundant OHLC/indicator caches and huge run history are omitted.
    return {key: wallet[key] for key in DISPLAY_FIELDS if key in wallet}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    # A malformed ledger must never be converted into a seemingly valid
    # account display; fail before touching an existing output file.
    state = json.loads(args.state.read_text(encoding="utf-8"))
    snapshot = view(state)
    encoded = json.dumps(snapshot, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"), allow_nan=False) + "\n"
    args.output.write_text(encoded, encoding="utf-8")


if __name__ == "__main__":
    main()
