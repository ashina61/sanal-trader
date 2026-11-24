"""Optional free Groq AI decision layer for verified paper-trading candidates.

No real orders, no exchange credentials. The deterministic engine remains the
source of truth for market freshness, sizing, exits and portfolio limits.
"""
import json
import urllib.request

API_URL = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "openai/gpt-oss-20b"


def _ask_groq(context, api_key, model):
    payload = {
        "model": model,
        "temperature": 0.1,
        "max_completion_tokens": 1024,
        "reasoning_effort": "low",
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content":
             "You review PAPER trades only. Choose ONE supplied candidate or WAIT. "
             "Do not invent prices, signals, tickers or trades. Maximize risk-adjusted "
             "simulation performance AFTER fees, not number of trades. "
             "The objective is growth of the ONE wallet's estimated net liquidation value. "
             "A candidate score is a ranking, NOT a return forecast or probability. "
             "Never call a high score or a few profitable closes proof of positive expectancy. "
             "Favor credible risk-adjusted compounding with a cash reserve. "
             "Use current candidate strength, recent and multi-hour momentum, "
             "volatility, regime and round-trip fees as primary evidence. "
             "Closed-trade win rate from fewer than 20 trades is a tiny sample; "
             "do NOT reject all approved current candidates solely because "
             "two recent paper closes lost money or past net return is negative. "
             "Still WAIT when no convincing positive risk-adjusted edge exists. "
             "Return only JSON: "
             '{"decision":"TRADE" or "WAIT","symbol":"ticker or null",'
             '"action":"BUY or SHORT or null","reason":"short explanation"}.'},
            {"role": "user", "content": json.dumps(context, ensure_ascii=False)},
        ],
    }
    req = urllib.request.Request(
        API_URL, data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": "Bearer " + api_key,
                 "Content-Type": "application/json",
                 "Accept": "application/json",
                 # Groq's edge may reject Python-urllib's default UA (HTTP 403).
                 "User-Agent": "SanalTraderPaperBot/1.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=9) as response:
        body = response.read(80_001)
    if len(body) > 80_000:
        raise ValueError("AI response too large")
    content = json.loads(body)["choices"][0]["message"]["content"]
    return json.loads(content)


def apply_ai_brain(plan, state, api_key="", model=DEFAULT_MODEL, ask_fn=None):
    """Return (validated plan, public diagnostics). Never widen trading risk.

    AI may wait or pick ONLY one of the engine-approved BUY/SHORT candidates.
    Stop-loss / take-profit SELL/COVER orders always bypass AI.
    On any AI failure, the deterministic plan continues unchanged.
    """
    if (plan.get("action") == "SELL" and
            str(plan.get("reason", "")).startswith("Risk azaltımı:")):
        return plan, {"status": "RISK_REDUCTION", "provider": "Rules",
                      "reason": "Verified weakening position closed to reduce "
                                "paper exposure; AI cannot override exits"}
    if plan.get("rotation") and plan.get("action") == "SELL":
        return plan, {"status": "ROTATION_EXIT", "provider": "Rules",
                      "reason": "Validated low-momentum position rotation; "
                                "no AI override and no automatic replacement"}
    if plan.get("action") in ("SELL", "COVER"):
        return plan, {"status": "PROTECTIVE_EXIT", "provider": "Groq",
                      "reason": "Protective exit does not require AI"}
    choices = plan.get("aiChoices") or []
    if not plan.get("order") or not choices:
        return plan, {"status": "NO_CANDIDATE", "provider": "Groq",
                      "reason": "No risk-approved entry candidates"}
    if not api_key:
        return plan, {"status": "NOT_CONFIGURED", "provider": "Groq",
                      "reason": "GROQ_API_KEY GitHub secret is missing"}
    context = {
        "marketRegime": plan.get("marketRegime"),
        "availableCashTry": round(float(state["cashTry"]), 2),
        "equityTry": round(float(state["equityTry"]), 2),
        "dailyOrders": int(state.get("todayOrders", 0)),
        "openLongs": list(state.get("holdings", {})),
        "openShorts": list(state.get("shorts", {})),
        "observedPerformance": state.get("performance") or {},
        "netWalletObjective": state.get("objective") or {},
        "roundTripPaperFeePct": 0.2,
        "closedOutcomeSampleSize": sum(
            1 for trade in state.get("trades", [])
            if isinstance(trade, dict) and trade.get("side") in ("sell", "cover")
        ),
        "recentClosedOutcomes": [
            {"symbol": trade.get("symbol"), "side": trade.get("side"),
             "netPnlTry": round(float(trade.get("realizedPnlTry", 0)), 2)}
            for trade in state.get("trades", [])
            if isinstance(trade, dict) and trade.get("side") in ("sell", "cover")
        ][:6],
        "candidates": choices,
    }
    try:
        answer = ask_fn(context) if ask_fn else _ask_groq(context, api_key, model)
        if not isinstance(answer, dict):
            raise ValueError("AI answer is not an object")
        reason = str(answer.get("reason") or "")[:180].replace("\n", " ").strip()
        decision = answer.get("decision")
        if decision == "WAIT":
            revised = dict(plan, action="WAIT", symbol=None, amountTry=None,
                           score=None, order=None,
                           reason="AI bekle kararı: " + (reason or "Teyit yetersiz"))
            return revised, {"status": "WAIT", "provider": "Groq",
                             "model": model, "reason": reason}
        if decision != "TRADE":
            raise ValueError("Unrecognized AI decision")
        selected = next((c for c in choices
                         if c["symbol"] == answer.get("symbol")
                         and c["action"] == answer.get("action")), None)
        if selected is None:
            raise ValueError("AI requested an unapproved trade")
        side = "buy" if selected["action"] == "BUY" else "short"
        name = selected["symbol"]
        amount = selected["amountTry"]
        rationale = "AI " + ("onayladı" if name == plan.get("symbol") else "seçti")
        trade_reason = rationale + " · " + (reason or "Teknik aday doğrulandı")
        revised = dict(plan, action=selected["action"], symbol=name,
                       setupTag=selected.get("setupTag", "hourly"),
                       contextKey=selected.get("contextKey"),
                       amountTry=amount, score=selected["score"],
                       sizeAudit=selected.get("sizeAudit"),
                       chartReadout=selected.get("chartReading"),
                       reason=trade_reason,
                       order=(name, side, amount, trade_reason))
        return revised, {"status": "TRADE", "provider": "Groq",
                         "model": model, "symbol": name, "reason": reason}
    except Exception as exc:
        # No key, HTTP response, private raw message or prompt is logged.
        http_status = getattr(exc, "code", None)
        detail = (f"HTTP {http_status}" if http_status is not None
                  else type(exc).__name__)
        return plan, {"status": "FALLBACK", "provider": "Groq",
                      "model": model, "reason": "AI unavailable/invalid: " + detail}
