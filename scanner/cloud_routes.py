"""Register Cloud Opportunity routes on existing FastAPI app.

No orders. Read-only opportunity feed for Flutter + health for worker.
Device token registration for FCM (credentials via ENV only).
"""

from __future__ import annotations

import os
from typing import Any

from fastapi import Depends, HTTPException, Query
from pydantic import BaseModel, Field

from scanner.cloud_worker import (
    opportunity_store,
    run_scan_once,
    start_worker_if_enabled,
)
from scanner.device_registry import device_registry
from scanner import fcm_dispatcher


class DeviceRegisterRequest(BaseModel):
    device_id: str = Field(min_length=4, max_length=128)
    fcm_token: str = Field(min_length=20, max_length=4096)
    platform: str = Field(default="android", max_length=16)
    enabled: bool = True


class DeviceIdRequest(BaseModel):
    device_id: str = Field(min_length=4, max_length=128)


def register_cloud_routes(app, *, require_owner):
    @app.get("/opportunities/latest")
    def list_cloud_opportunities(
        _: str = Depends(require_owner),
        limit: int = Query(default=20, ge=1, le=50),
        only_fresh: bool = Query(default=True),
        min_score: float = Query(default=70, ge=0, le=100),
        side: str | None = Query(default=None),
    ) -> dict:
        rows = opportunity_store.list_recent(
            limit=limit,
            only_fresh=only_fresh,
            min_score=min_score,
            side=side,
        )
        return {
            "opportunities": rows,
            "count": len(rows),
            "source": "cloud_worker",
            "message": (
                "NO VALID OPPORTUNITY"
                if not rows
                else f"{len(rows)} opportunities"
            ),
        }

    @app.get("/opportunities/health")
    def opportunities_health() -> dict:
        h = opportunity_store.health()
        h["status"] = "ok"
        h["cloud_worker_enabled"] = os.getenv("CLOUD_WORKER_ENABLED", "").lower() in (
            "1",
            "true",
            "yes",
            "on",
        )
        h["orders_from_cloud"] = False
        h["fcm_configured"] = fcm_dispatcher.is_configured()
        h["devices"] = device_registry.health()
        h["interval_seconds"] = int(os.getenv("CLOUD_WORKER_INTERVAL_SEC", "90"))
        return h

    @app.post("/opportunities/scan-now")
    def scan_now(_: str = Depends(require_owner)) -> dict:
        """Owner-triggered one-shot scan (useful when worker disabled)."""
        try:
            result = run_scan_once()
        except Exception as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return {"status": "ok", "result": result}

    @app.post("/devices/register")
    def register_device(
        body: DeviceRegisterRequest, _: str = Depends(require_owner)
    ) -> dict:
        """Register / rotate FCM device token. No secrets in response."""
        try:
            rec = device_registry.register(
                device_id=body.device_id,
                fcm_token=body.fcm_token,
                platform=body.platform,
                enabled=body.enabled,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        return {
            "status": "ok",
            "device": rec.to_dict(),
            "message": "token registered (rotation supported)",
        }

    @app.post("/devices/disable")
    def disable_device(
        body: DeviceIdRequest, _: str = Depends(require_owner)
    ) -> dict:
        ok = device_registry.disable(body.device_id)
        if not ok:
            raise HTTPException(status_code=404, detail="device not found")
        return {"status": "ok", "disabled": True}

    @app.post("/devices/remove")
    def remove_device(
        body: DeviceIdRequest, _: str = Depends(require_owner)
    ) -> dict:
        ok = device_registry.remove(body.device_id)
        if not ok:
            raise HTTPException(status_code=404, detail="device not found")
        return {"status": "ok", "removed": True}

    @app.get("/devices/list")
    def list_devices(_: str = Depends(require_owner)) -> dict:
        rows = device_registry.list_devices()
        return {"devices": rows, "count": len(rows)}

    # Start background worker once routes are registered (env-gated)
    start_worker_if_enabled()
