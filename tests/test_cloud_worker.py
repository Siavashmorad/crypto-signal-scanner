"""Unit tests for cloud worker — no live Tabdeal required for core logic."""

from __future__ import annotations

from scanner.cloud_worker import (
    CloudOpportunity,
    OpportunityStore,
    _fingerprint,
    _rank_key,
    opportunity_store,
)


def test_fingerprint_stable_shape():
    fp = _fingerprint("BTCUSDT", "LONG", "15m", 65000.0)
    assert isinstance(fp, str) and len(fp) == 16


def test_opportunity_store_upsert_and_list():
    store = OpportunityStore(max_items=10)
    now = 1_700_000_000_000
    opp = CloudOpportunity(
        symbol="BTCUSDT",
        side="LONG",
        timeframe="15m",
        entry=65000.0,
        stop_loss=64000.0,
        take_profit=[67000.0],
        score=85.0,
        confidence=85.0,
        regime="TRENDING_BULL",
        data_health="LIVE",
        reasons=["EMA trend"],
        source="scanner",
        tv_agree=False,
        fingerprint="abc123def4567890",
        status="VALIDATED",
        created_at_ms=now,
        updated_at_ms=now,
    )
    ok, reason = store.upsert(opp)
    assert ok and reason == "ok"
    rows = store.list_recent(limit=5, only_fresh=False, min_score=70)
    assert len(rows) == 1
    assert rows[0]["symbol"] == "BTCUSDT"
    assert rows[0]["side"] == "LONG"
    assert rows[0]["risk_reward"] is not None


def test_opportunity_store_expire():
    store = OpportunityStore(max_items=5)
    old = CloudOpportunity(
        symbol="ETHUSDT",
        side="SHORT",
        timeframe="15m",
        entry=3000.0,
        stop_loss=3100.0,
        take_profit=[2800.0],
        score=80.0,
        confidence=80.0,
        regime="TRENDING_BEAR",
        data_health="LIVE",
        reasons=[],
        source="scanner",
        tv_agree=False,
        fingerprint="oldfingerprint01",
        status="VALIDATED",
        created_at_ms=1,
        updated_at_ms=1,
    )
    store.upsert(old)
    n = store.expire_stale()
    assert n >= 1
    rows = store.list_recent(only_fresh=True, min_score=0)
    assert all(r["symbol"] != "ETHUSDT" or r.get("status") != "EXPIRED" for r in rows)


def test_rank_prefers_tv_agree():
    a = CloudOpportunity(
        symbol="BTCUSDT",
        side="LONG",
        timeframe="15m",
        entry=1,
        stop_loss=0.9,
        take_profit=[1.2],
        score=80,
        confidence=80,
        regime="UNKNOWN",
        data_health="LIVE",
        reasons=[],
        source="scanner",
        tv_agree=False,
        fingerprint="a",
        status="VALIDATED",
        created_at_ms=0,
        updated_at_ms=0,
    )
    b = CloudOpportunity(
        symbol="BTCUSDT",
        side="LONG",
        timeframe="15m",
        entry=1,
        stop_loss=0.9,
        take_profit=[1.2],
        score=78,
        confidence=78,
        regime="UNKNOWN",
        data_health="LIVE",
        reasons=[],
        source="scanner+tv",
        tv_agree=True,
        fingerprint="b",
        status="VALIDATED",
        created_at_ms=0,
        updated_at_ms=0,
    )
    hints = {"BTCUSDT": "LONG"}
    assert _rank_key(b, hints) > _rank_key(a, hints)


def test_global_store_health_shape():
    h = opportunity_store.health()
    assert "worker_running" in h
    assert h["orders_from_worker"] is False
