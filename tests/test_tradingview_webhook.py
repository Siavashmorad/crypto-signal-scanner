"""TradingView webhook parsing, auth, stale, duplicate — no orders."""

import os

import pytest
from fastapi.testclient import TestClient

from auth.single_user import password_hash
from scanner.tradingview_webhook import (
    alert_store,
    normalize_side,
    normalize_symbol,
    parse_tradingview_payload,
    verify_webhook_secret,
)


@pytest.fixture(autouse=True)
def _clean_store(monkeypatch):
    alert_store.clear()
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "tv-test-secret")
    yield
    alert_store.clear()


def test_normalize_symbol_binance_prefix():
    assert normalize_symbol("BINANCE:BTCUSDT") == "BTCUSDT"
    assert normalize_symbol("btcusdt.p") == "BTCUSDT"


def test_normalize_side():
    assert normalize_side("buy") == "LONG"
    assert normalize_side("SELL") == "SHORT"
    assert normalize_side("maybe") == "NEUTRAL"


def test_parse_full_payload():
    a = parse_tradingview_payload(
        {
            "symbol": "ETHUSDT",
            "exchange": "BINANCE",
            "timeframe": "15m",
            "price": 3000.5,
            "signal": "LONG",
            "timestamp": 1_700_000_000,
            "indicators": {"rsi": 55.2, "atr": 12.0},
            "volume": 999,
        }
    )
    assert a.symbol == "ETHUSDT"
    assert a.signal == "LONG"
    assert a.price == 3000.5
    assert a.indicators["rsi"] == 55.2
    assert "macd" not in a.indicators  # not invented


def test_parse_missing_indicators_ok():
    a = parse_tradingview_payload({"symbol": "SOLUSDT", "signal": "SHORT"})
    assert a.indicators == {}
    assert a.price is None


def test_parse_rejects_bad_symbol():
    with pytest.raises(ValueError):
        parse_tradingview_payload({"symbol": "x", "signal": "LONG"})


def test_stale_detection():
    a = parse_tradingview_payload(
        {
            "symbol": "BTCUSDT",
            "signal": "LONG",
            "timestamp": 1_000_000,  # ancient ms-ish seconds treated
        }
    )
    # force old timestamp
    a.timestamp_ms = 1
    assert a.is_stale(max_age_sec=60) is True


def test_duplicate_fingerprint():
    p = {"symbol": "XRPUSDT", "signal": "LONG", "timeframe": "15m", "timestamp": 1_800_000_000}
    a1 = parse_tradingview_payload(p)
    a2 = parse_tradingview_payload(p)
    assert a1.fingerprint == a2.fingerprint
    ok1, _ = alert_store.add(a1)
    ok2, reason = alert_store.add(a2)
    assert ok1 is True
    assert ok2 is False
    assert reason == "duplicate"


def test_verify_secret(monkeypatch):
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "abc")
    assert verify_webhook_secret("abc") is True
    assert verify_webhook_secret("wrong") is False
    assert verify_webhook_secret(None) is False
    monkeypatch.delenv("TRADINGVIEW_WEBHOOK_SECRET", raising=False)
    assert verify_webhook_secret("abc") is False


def test_webhook_http_accept(monkeypatch):
    monkeypatch.setenv("TRADINGVIEW_WEBHOOK_SECRET", "tv-test-secret")
    from main import app

    client = TestClient(app)
    r = client.post(
        "/webhook/tradingview?secret=tv-test-secret",
        json={"symbol": "BTCUSDT", "signal": "LONG", "price": 65000, "timeframe": "15m"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "accepted"
    assert body["alert"]["symbol"] == "BTCUSDT"
    assert body["alert"]["signal"] == "LONG"


def test_webhook_http_reject_bad_secret():
    from main import app

    client = TestClient(app)
    r = client.post(
        "/webhook/tradingview?secret=wrong",
        json={"symbol": "BTCUSDT", "signal": "LONG"},
    )
    assert r.status_code == 401


def test_webhook_health():
    from main import app

    client = TestClient(app)
    r = client.get("/webhook/tradingview/health")
    assert r.status_code == 200
    assert r.json()["orders_from_webhook"] is False
