"""FCM push dispatcher — credentials from ENV only. Never places orders.

Uses legacy FCM HTTP API when FCM_SERVER_KEY is set.
Graceful no-op when credentials missing.
"""

from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from typing import Any

from scanner.cloud_worker import CloudOpportunity
from scanner.device_registry import device_registry

logger = logging.getLogger("signalyab.fcm")

FCM_ENDPOINT = "https://fcm.googleapis.com/fcm/send"


def _server_key() -> str | None:
    key = (os.getenv("FCM_SERVER_KEY") or "").strip()
    return key or None


def is_configured() -> bool:
    return bool(_server_key()) or bool(
        (os.getenv("FIREBASE_CREDENTIALS_JSON") or "").strip()
    )


def build_payload(opp: CloudOpportunity) -> dict[str, Any]:
    """Notification + data payload for SignalYab deep-link."""
    rr = None
    if opp.entry and opp.stop_loss and opp.take_profit:
        risk = abs(opp.entry - opp.stop_loss)
        reward = abs(opp.take_profit[0] - opp.entry) if opp.take_profit else 0
        if risk > 0:
            rr = round(reward / risk, 2)
    title = f"SignalYab {opp.symbol} {opp.side}"
    body_parts = [
        f"Entry {opp.entry}",
        f"SL {opp.stop_loss}",
    ]
    if opp.take_profit:
        body_parts.append(f"TP1 {opp.take_profit[0]}")
    if rr is not None:
        body_parts.append(f"R:R {rr}")
    body_parts.append(f"Score {opp.score:.0f}")
    body_parts.append(f"Conf {opp.confidence:.0f}")
    if opp.regime:
        body_parts.append(opp.regime)
    body = " | ".join(body_parts)
    data = {
        "type": "signal_opportunity",
        "opportunity_id": opp.fingerprint,
        "symbol": opp.symbol,
        "side": opp.side,
        "entry": str(opp.entry),
        "stop_loss": str(opp.stop_loss),
        "tp1": str(opp.take_profit[0]) if opp.take_profit else "",
        "risk_reward": str(rr) if rr is not None else "",
        "score": str(opp.score),
        "confidence": str(opp.confidence),
        "regime": opp.regime or "",
        "timestamp_ms": str(opp.updated_at_ms),
        "timestamp": str(opp.updated_at_ms),
        "source": opp.source,
        "deep_link": f"signalyab://opportunity/{opp.symbol}/{opp.side}/{opp.fingerprint}",
    }
    return {
        "notification": {
            "title": title,
            "body": body,
            "sound": "default",
            "click_action": "FLUTTER_NOTIFICATION_CLICK",
            "android_channel_id": "signalyab_futures_opportunities",
        },
        "data": data,
        "priority": "high",
        "content_available": True,
    }


def _post_legacy(server_key: str, registration_ids: list[str], payload: dict[str, Any]) -> dict[str, Any]:
    body = {
        "registration_ids": registration_ids[:500],
        **payload,
    }
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        FCM_ENDPOINT,
        data=data,
        method="POST",
        headers={
            "Authorization": f"key={server_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {"success": 0}
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")[:500]
        logger.warning("FCM HTTP %s: %s", exc.code, err_body)
        return {"success": 0, "failure": len(registration_ids), "error": str(exc.code)}
    except Exception as exc:
        logger.warning("FCM send failed: %s", exc)
        return {"success": 0, "failure": len(registration_ids), "error": str(exc)}


def dispatch_opportunity(opp: CloudOpportunity) -> dict[str, Any]:
    """Send push to all enabled registered devices. No-op if not configured."""
    key = _server_key()
    tokens = device_registry.enabled_tokens()
    result: dict[str, Any] = {
        "configured": bool(key),
        "tokens": len(tokens),
        "sent": 0,
        "skipped_reason": None,
    }
    if not key:
        result["skipped_reason"] = "FCM_SERVER_KEY not set"
        logger.info("FCM skip: no server key (credential required)")
        return result
    if not tokens:
        result["skipped_reason"] = "no enabled device tokens"
        return result
    payload = build_payload(opp)
    api = _post_legacy(key, tokens, payload)
    success = int(api.get("success") or 0)
    result["sent"] = success
    result["fcm_response"] = {
        "success": success,
        "failure": api.get("failure"),
    }
    logger.info(
        "FCM dispatch %s %s → tokens=%s success=%s",
        opp.symbol,
        opp.side,
        len(tokens),
        success,
    )
    return result
