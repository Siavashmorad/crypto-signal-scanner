"""Unit tests for cloud worker — no live Tabdeal required for core logic."""

from __future__ import annotations

from scanner.cloud_worker import (
    CloudOpportunity,
    OpportunityStore,
    _fingerprint,
    _rank_key,
    _try_notify,
    build_universe,
    opportunity_store,
)
from scanner.device_registry import DeviceRegistry
from scanner.fcm_dispatcher import build_payload, is_configured


def test_fingerprint_stable_shape():
    fp = _fingerprint("BTCUSDT", "LONG", "15m", 65000.0)
    assert isinstance(fp, str) and len(fp) == 16
