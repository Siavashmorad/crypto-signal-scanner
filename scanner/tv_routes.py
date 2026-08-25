"""Register TradingView webhook routes on an existing FastAPI app."""

from __future__ import annotations

import os

from fastapi import Depends, Header, HTTPException, Query, Request


def register_tradingview_routes(app, *, require_owner):
    from scanner.tradingview_webhook import (
        alert_store,
        parse_tradingview_payload,
        verify_webhook_secret,
    )

    @app.post("/webhook/tradingview")
    async def tradingview_webhook(
        request: Request,
        secret: str | None = Query(default=None),
        x_signalyab_secret: str | None = Header(default=None, alias="X-SignalYab-Secret"),
    ) -> dict:
        try:
            payload = await request.json()
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid JSON body") from exc
        if not isinstance(payload, dict):
            raise HTTPException(status_code=400, detail="JSON object required")
        body_secret = payload.pop("secret", None)
        if not verify_webhook_secret(secret or body_secret, x_signalyab_secret):
            raise HTTPException(status_code=401, detail="Invalid or missing webhook secret")
        try:
            alert = parse_tradingview_payload(payload)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if alert.is_stale():
            return {
                "status": "rejected",
                "reason": "STALE_SIGNAL",
                "message": "سیگنال منقضی است — معامله نمی‌شود",
                "alert": alert.to_dict(),
            }
        ok, reason = alert_store.add(alert)
        if not ok:
            return {
                "status": "rejected",
                "reason": reason.upper(),
                "message": "سیگنال تکراری نادیده گرفته شد",
                "fingerprint": alert.fingerprint,
            }
        return {
            "status": "accepted",
            "message": "هشدار TradingView ثبت شد — تصمیم نهایی با SignalYab و تأیید کاربر است",
            "alert": alert.to_dict(),
        }

    @app.get("/webhook/tradingview/alerts")
    def list_tradingview_alerts(
        _: str = Depends(require_owner),
        limit: int = Query(default=30, ge=1, le=100),
        only_fresh: bool = Query(default=True),
        symbol: str | None = Query(default=None),
    ) -> dict:
        rows = alert_store.list_recent(limit=limit, only_fresh=only_fresh, symbol=symbol)
        return {"alerts": rows, "count": len(rows), "source": "tradingview"}

    @app.get("/webhook/tradingview/health")
    def tradingview_webhook_health() -> dict:
        return {
            "status": "ok",
            "webhook": "tradingview",
            "secret_configured": bool(os.getenv("TRADINGVIEW_WEBHOOK_SECRET")),
            "orders_from_webhook": False,
        }
