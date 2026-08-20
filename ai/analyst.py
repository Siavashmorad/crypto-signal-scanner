from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any


SYSTEM_PROMPT = """You are a crypto market analyst assisting a signal-only application.
Analyze only the supplied market/signal data. Do not invent prices, indicators, news, or certainty.
Return practical but cautious analysis for a human who will manually decide whether to trade.
Never instruct the app to place, modify, or close an exchange order automatically.
Return JSON with these keys:
summary, trend, momentum, risk_level, signal_quality, bull_case, bear_case, invalidation,
recommendation, confidence, reasons.
confidence must be an integer from 0 to 100 and represents analytical confidence, not probability of profit.
recommendation must be one of: WATCH, LONG_BIAS, SHORT_BIAS, AVOID.
"""


def _extract_output_text(payload: dict[str, Any]) -> str:
    text = payload.get("output_text")
    if isinstance(text, str) and text.strip():
        return text.strip()

    chunks: list[str] = []
    for item in payload.get("output", []):
        if not isinstance(item, dict):
            continue
        for content in item.get("content", []):
            if isinstance(content, dict) and content.get("type") in {"output_text", "text"}:
                value = content.get("text")
                if isinstance(value, str):
                    chunks.append(value)
    return "".join(chunks).strip()


def analyze_market(signal: dict[str, Any]) -> dict[str, Any]:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")

    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini").strip()
    endpoint = os.getenv("OPENAI_RESPONSES_URL", "https://api.openai.com/v1/responses").strip()

    user_prompt = (
        "Analyze this already-computed market signal. Use only these facts and clearly separate "
        "observation from interpretation. Data:\n" + json.dumps(signal, ensure_ascii=False, separators=(",", ":"))
    )
    body = {
        "model": model,
        "input": [
            {"role": "system", "content": [{"type": "input_text", "text": SYSTEM_PROMPT}]},
            {"role": "user", "content": [{"type": "input_text", "text": user_prompt}]},
        ],
        "temperature": 0.2,
    }

    request = urllib.request.Request(
        endpoint,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise RuntimeError(f"AI provider error: HTTP {exc.code}: {detail}") from exc
    except (urllib.error.URLError, TimeoutError) as exc:
        raise RuntimeError("AI provider is unavailable") from exc

    text = _extract_output_text(payload)
    if not text:
        raise RuntimeError("AI provider returned no analysis")

    try:
        result = json.loads(text)
    except json.JSONDecodeError:
        result = {
            "summary": text,
            "trend": "UNKNOWN",
            "momentum": "UNKNOWN",
            "risk_level": "UNKNOWN",
            "signal_quality": "UNKNOWN",
            "bull_case": "",
            "bear_case": "",
            "invalidation": "",
            "recommendation": "WATCH",
            "confidence": 0,
            "reasons": [],
        }

    if not isinstance(result, dict):
        raise RuntimeError("AI provider returned an invalid analysis object")

    result["symbol"] = signal.get("symbol")
    result["side"] = signal.get("side")
    return result
