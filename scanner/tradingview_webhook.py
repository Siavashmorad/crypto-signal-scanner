"""TradingView alert intake — validation only, never places orders.

TradingView → webhook → store → SignalYab consumes → Quant/Gate → user confirm.
No fake indicators. Missing fields stay missing.
"""

from __future__ import annotations

import hashlib
import hmac
import os
import threading
import time
from dataclasses import dataclass, field, asdict
from typing import Any

WEBHOOK_SECRET_ENV = "TRADINGVIEW_WEBHOOK_SECRET"
MAX_ALERTS = 200
DEFAULT_MAX_AGE_SEC = 15 * 60  # 15 minutes → STALE


def _now_ms() -> int:
    return int(time.time() * 1000)


@dataclass
class TradingViewAlert:
    symbol: str
    signal: str  # LONG | SHORT | NEUTRAL
    exchange: str = ""
    timeframe: str = ""
    price: float | None = None
    timestamp_ms: int = 0
    volume: float | None = None
    indicators: dict[str, float] = field(default_factory=dict)
    raw_keys: list[str] = field(default_factory=list)
    received_at_ms: int = 0
    fingerprint: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "symbol": self.symbol,
            "signal": self.signal,
            "exchange": self.exchange,
            "timeframe": self.timeframe,
            "price": self.price,
            "timestamp_ms": self.timestamp_ms,
            "volume": self.volume,
            "indicators": dict(self.indicators),
            "received_at_ms": self.received_at_ms,
            "fingerprint": self.fingerprint,
            "source": "tradingview",
        }

    def is_stale(self, max_age_sec: int = DEFAULT_MAX_AGE_SEC, now_ms: int | None = None) -> bool:
        t = now_ms if now_ms is not None else _now_ms()
        base = self.timestamp_ms if self.timestamp_ms > 0 else self.received_at_ms
        if base <= 0:
            return True
        return (t - base) > max_age_sec * 1000


def normalize_symbol(raw: str) -> str:
    s = (raw or "").strip()
    if ":" in s:
        s = s.split(":")[-1]
    if s.upper().endswith(".P"):
        s = s[:-2]
    s = s.upper().replace("/", "").replace("-", "").replace(".", "")
    return s


def normalize_side(raw: Any) -> str:
    s = str(raw or "").strip().upper()
    if s in ("LONG", "BUY", "BULL", "CALL"):
        return "LONG"
    if s in ("SHORT", "SELL", "BEAR", "PUT"):
        return "SHORT"
    return "NEUTRAL"


def _as_float(v: Any) -> float | None:
    if v is None or v == "":
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_tradingview_payload(payload: dict[str, Any]) -> TradingViewAlert:
    """Parse only fields that exist. Never invent RSI/MACD/etc."""
    if not isinstance(payload, dict):
        raise ValueError("payload must be a JSON object")

    symbol = normalize_symbol(
        str(payload.get("symbol") or payload.get("ticker") or payload.get("sym") or "")
    )
    if not symbol or len(symbol) < 3:
        raise ValueError("symbol missing or invalid")

    signal = normalize_side(
        payload.get("signal")
        or payload.get("side")
        or payload.get("action")
        or payload.get("order")
        or ""
    )

    exchange = str(payload.get("exchange") or payload.get("exch") or "").strip().upper()
    timeframe = str(payload.get("timeframe") or payload.get("interval") or payload.get("tf") or "").strip()

    price = _as_float(payload.get("price") or payload.get("close") or payload.get("last"))
    volume = _as_float(payload.get("volume") or payload.get("vol"))

    ts = payload.get("timestamp") or payload.get("time") or payload.get("ts")
    timestamp_ms = 0
    if ts is not None:
        try:
            tsf = float(ts)
            timestamp_ms = int(tsf * 1000) if tsf < 1e12 else int(tsf)
        except (TypeError, ValueError):
            timestamp_ms = 0

    indicators: dict[str, float] = {}
    raw_ind = payload.get("indicators")
    if isinstance(raw_ind, dict):
        for k, v in raw_ind.items():
            fv = _as_float(v)
            if fv is not None:
                indicators[str(k).lower()] = fv
    for key in ("rsi", "macd", "ema", "atr", "adx", "vwap", "cci", "roc"):
        if key in payload and key not in indicators:
            fv = _as_float(payload.get(key))
            if fv is not None:
                indicators[key] = fv

    received = _now_ms()
    if timestamp_ms <= 0:
        timestamp_ms = received

    fp_src = f"{symbol}:{signal}:{timeframe}:{timestamp_ms // 60000}"
    fingerprint = hashlib.sha256(fp_src.encode()).hexdigest()[:16]

    return TradingViewAlert(
        symbol=symbol,
        signal=signal,
        exchange=exchange,
        timeframe=timeframe,
        price=price,
        timestamp_ms=timestamp_ms,
        volume=volume,
        indicators=indicators,
        raw_keys=sorted(str(k) for k in payload.keys()),
        received_at_ms=received,
        fingerprint=fingerprint,
    )


def verify_webhook_secret(provided: str | None, header_token: str | None = None) -> bool:
    """Constant-time compare against TRADINGVIEW_WEBHOOK_SECRET env."""
    expected = os.getenv(WEBHOOK_SECRET_ENV, "")
    if not expected:
        return False
    candidates = [c for c in (provided, header_token) if c]
    if not candidates:
        return False
    for c in candidates:
        if hmac.compare_digest(str(c), expected):
            return True
    return False


class AlertStore:
    """In-memory ring buffer of recent TV alerts (process lifetime)."""

    def __init__(self, max_items: int = MAX_ALERTS) -> None:
        self._lock = threading.Lock()
        self._items: list[TradingViewAlert] = []
        self._fps: set[str] = set()
        self._max = max_items

    def add(self, alert: TradingViewAlert) -> tuple[bool, str]:
        with self._lock:
            if alert.fingerprint in self._fps:
                return False, "duplicate"
            self._items.append(alert)
            self._fps.add(alert.fingerprint)
            while len(self._items) > self._max:
                old = self._items.pop(0)
                self._fps.discard(old.fingerprint)
            return True, "ok"

    def list_recent(
        self,
        *,
        limit: int = 50,
        only_fresh: bool = True,
        max_age_sec: int = DEFAULT_MAX_AGE_SEC,
        symbol: str | None = None,
    ) -> list[dict[str, Any]]:
        now = _now_ms()
        with self._lock:
            rows = list(reversed(self._items))
        out: list[dict[str, Any]] = []
        for a in rows:
            if symbol and a.symbol != normalize_symbol(symbol):
                continue
            if only_fresh and a.is_stale(max_age_sec=max_age_sec, now_ms=now):
                continue
            if a.signal == "NEUTRAL":
                continue
            d = a.to_dict()
            d["stale"] = a.is_stale(max_age_sec=max_age_sec, now_ms=now)
            out.append(d)
            if len(out) >= limit:
                break
        return out

    def clear(self) -> None:
        with self._lock:
            self._items.clear()
            self._fps.clear()


alert_store = AlertStore()
