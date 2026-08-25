"""Register Cloud Opportunity routes on existing FastAPI app.

No orders. Read-only opportunity feed for Flutter + health for worker.
"""

from __future__ import annotations

import os

from fastapi import Depends, HTTPException, Query

from scanner.cloud_worker import (
    opportunity_store,
    run_scan_once,
    start_worker_if_enabled,
)


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
        return h

    @app.post("/opportunities/scan-now")
    def scan_now(_: str = Depends(require_owner)) -> dict:
        """Owner-triggered one-shot scan (useful when worker disabled)."""
        try:
            result = run_scan_once()
        except Exception as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return {"status": "ok", "result": result}

    # Start background worker once routes are registered (env-gated)
    start_worker_if_enabled()
