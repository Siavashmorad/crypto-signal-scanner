"""Cloud Market Intelligence Worker — independent of Flutter process lifetime.

Reuses existing scanner.engine.scan_symbol + best_market helpers.
Does NOT invent indicators or market data.
Does NOT place orders. TV alerts are hints only.

Enable with env CLOUD_WORKER_ENABLED=true (default false on free-tier safety).
FCM push is optional and requires FCM_SERVER_KEY (never committed).
"""

from __future__ import annotations

import hashlib
import logging
import os
import threading
import time
from dataclasses import asdict, dataclass
from typing import Any

from data.tabdeal import TabdealPublicClient
from scanner.best_market import extract_symbols
from scanner.engine import scan_symbol
from scanner.tradingview_webhook import alert_store

logger = logging.getLogger("signalyab.cloud_worker")

DEFAULT_INTERVAL_SEC = int(os.getenv("CLOUD_WORKER_INTERVAL_SEC", "90"))
DEFAULT_MAX_SYMBOLS = int(os.getenv("CLOUD_WORKER_MAX_SYMBOLS", "16"))
DEFAULT_TIMEFRAME = os.getenv("CLOUD_WORKER_TIMEFRAME", "15m")
DEFAULT_CAPITAL = float(os.getenv("CLOUD_WORKER_CAPITAL", "1000"))
DEFAULT_RISK_PCT = float(os.getenv("CLOUD_WORKER_RISK_PERCENT", "1.0"))
MIN_SCORE = float(os.getenv("CLOUD_WORKER_MIN_SCORE", "70"))
MAX_OPPORTUNITIES = 100
DEFAULT_MAX_AGE_SEC = int(os.getenv("CLOUD_WORKER_OPPORTUNITY_TTL_SECONDS", str(15 * 60)))
NOTIFY_COOLDOWN_SEC = int(
    os.getenv(
        "CLOUD_WORKER_NOTIFICATION_COOLDOWN_SECONDS",
        os.getenv("CLOUD_NOTIFY_COOLDOWN_SEC", "900"),
    )
)

PRIORITY_SYMBOLS = (
    "BTCUSDT",
    "ETHUSDT",
    "SOLUSDT",
    "XRPUSDT",
    "DOGEUSDT",
    "ADAUSDT",
    "SUIUSDT",
)


def _now_ms() -> int:
    return int(time.time() * 1000)


@dataclass
class CloudOpportunity:
    symbol: str
    side: str  # LONG | SHORT
    timeframe: str
    entry: float
    stop_loss: float
    take_profit: list[float]
    score: float
    confidence: float
    regime: str
    data_health: str  # LIVE | DEGRADED | STALE | INSUFFICIENT_DATA
    reasons: list[str]
    source: str  # scanner | scanner+tv
    tv_agree: bool
    fingerprint: str
    status: str  # NEW | VALIDATED | NOTIFIED | EXPIRED | REJECTED
    created_at_ms: int
    updated_at_ms: int
    notified_at_ms: int = 0
    higher_tf: str = ""  # e.g. 1h alignment note when available

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["tp1"] = self.take_profit[0] if self.take_profit else None
        d["tp2"] = self.take_profit[1] if len(self.take_profit) > 1 else None
        d["tp3"] = self.take_profit[2] if len(self.take_profit) > 2 else None
        rr = None
        if self.entry and self.stop_loss and self.take_profit:
            risk = abs(self.entry - self.stop_loss)
            reward = abs(self.take_profit[0] - self.entry) if self.take_profit else 0
            if risk > 0:
                rr = round(reward / risk, 2)
        d["risk_reward"] = rr
        return d

    def is_stale(self, max_age_sec: int = DEFAULT_MAX_AGE_SEC, now_ms: int | None = None) -> bool:
        t = now_ms if now_ms is not None else _now_ms()
        return (t - self.updated_at_ms) > max_age_sec * 1000


class OpportunityStore:
    """In-memory ring of cloud opportunities (process lifetime)."""

    def __init__(self, max_items: int = MAX_OPPORTUNITIES) -> None:
        self._lock = threading.Lock()
        self._items: list[CloudOpportunity] = []
        self._fps: set[str] = set()
        self._max = max_items
        self._notified_fp: dict[str, int] = {}  # fingerprint -> notified_at_ms
        self.last_scan_at_ms: int = 0
        self.last_success_at_ms: int = 0
        self.last_scan_detail: str = ""
        self.last_error: str = ""
        self.last_scanned_count: int = 0
        self.last_opportunity_count: int = 0
        self.notifications_sent: int = 0
        self.worker_running: bool = False
        self.started_at_ms: int = 0

    def upsert(self, opp: CloudOpportunity) -> tuple[bool, str]:
        with self._lock:
            if opp.fingerprint in self._fps:
                for i, existing in enumerate(self._items):
                    if existing.fingerprint == opp.fingerprint:
                        self._items[i] = opp
                        return True, "updated"
                return False, "duplicate"
            self._items.append(opp)
            self._fps.add(opp.fingerprint)
            while len(self._items) > self._max:
                old = self._items.pop(0)
                self._fps.discard(old.fingerprint)
            return True, "ok"

    def list_recent(
        self,
        *,
        limit: int = 20,
        only_fresh: bool = True,
        min_score: float = 0,
        side: str | None = None,
    ) -> list[dict[str, Any]]:
        now = _now_ms()
        with self._lock:
            rows = list(reversed(self._items))
        out: list[dict[str, Any]] = []
        for o in rows:
            if only_fresh and o.is_stale(now_ms=now):
                continue
            if o.score < min_score:
                continue
            if side and o.side.upper() != side.upper():
                continue
            if o.status in ("EXPIRED", "REJECTED"):
                continue
            d = o.to_dict()
            d["stale"] = o.is_stale(now_ms=now)
            out.append(d)
            if len(out) >= limit:
                break
        return out

    def top(self, *, min_score: float = MIN_SCORE) -> dict[str, Any] | None:
        rows = self.list_recent(limit=1, only_fresh=True, min_score=min_score)
        return rows[0] if rows else None

    def should_notify(self, fingerprint: str, cooldown_sec: int = NOTIFY_COOLDOWN_SEC) -> bool:
        now = _now_ms()
        with self._lock:
            last = self._notified_fp.get(fingerprint, 0)
            if last and (now - last) < cooldown_sec * 1000:
                return False
            return True

    def mark_notified(self, fingerprint: str) -> None:
        with self._lock:
            self._notified_fp[fingerprint] = _now_ms()
            for o in self._items:
                if o.fingerprint == fingerprint:
                    o.status = "NOTIFIED"
                    o.notified_at_ms = self._notified_fp[fingerprint]
                    o.updated_at_ms = o.notified_at_ms

    def expire_stale(self) -> int:
        now = _now_ms()
        n = 0
        with self._lock:
            for o in self._items:
                if o.status not in ("EXPIRED", "REJECTED") and o.is_stale(now_ms=now):
                    o.status = "EXPIRED"
                    o.updated_at_ms = now
                    n += 1
        return n

    def health(self) -> dict[str, Any]:
        now = _now_ms()
        with self._lock:
            fresh = sum(
                1
                for o in self._items
                if not o.is_stale() and o.status not in ("EXPIRED", "REJECTED")
            )
            top_sym = None
            for o in reversed(self._items):
                if not o.is_stale() and o.status not in ("EXPIRED", "REJECTED"):
                    top_sym = f"{o.symbol} {o.side} score={o.score}"
                    break
            uptime_sec = (
                int((now - self.started_at_ms) / 1000) if self.started_at_ms else 0
            )
        return {
            "worker_running": self.worker_running,
            "last_scan_at": self.last_scan_at_ms,
            "last_scan_at_ms": self.last_scan_at_ms,
            "last_success_at_ms": self.last_success_at_ms,
            "last_scan_detail": self.last_scan_detail,
            "last_error": self.last_error,
            "last_scanned_count": self.last_scanned_count,
            "symbols_scanned": self.last_scanned_count,
            "last_opportunity_count": self.last_opportunity_count,
            "opportunities_found": self.last_opportunity_count,
            "fresh_opportunities": fresh,
            "notifications_sent": self.notifications_sent,
            "top_opportunity": top_sym,
            "uptime_seconds": uptime_sec,
            "orders_from_worker": False,
            "push_configured": bool(
                os.getenv("FCM_SERVER_KEY") or os.getenv("FIREBASE_CREDENTIALS_JSON")
            ),
        }


opportunity_store = OpportunityStore()


def _tv_hints() -> dict[str, str]:
    """symbol → LONG/SHORT from fresh TV alerts only."""
    hints: dict[str, str] = {}
    try:
        rows = alert_store.list_recent(limit=50, only_fresh=True)
        for row in rows:
            sym = str(row.get("symbol", "")).upper()
            sig = str(row.get("signal", "")).upper()
            if sym and sig in ("LONG", "SHORT"):
                hints[sym] = sig
    except Exception:
        pass
    return hints


def _fingerprint(symbol: str, side: str, timeframe: str, entry: float) -> str:
    bucket = int(entry * 100) // 10
    src = f"{symbol}:{side}:{timeframe}:{bucket}:{_now_ms() // 60000}"
    return hashlib.sha256(src.encode()).hexdigest()[:16]


def _rank_key(opp: CloudOpportunity, hints: dict[str, str] | None = None) -> tuple:
    """Higher tuple sorts first. TV-agree elevates even if score slightly lower."""
    tv_bonus = 2 if opp.tv_agree else 0
    if not opp.tv_agree and hints:
        if hints.get(opp.symbol.upper()) == opp.side.upper():
            tv_bonus = 1
    return (tv_bonus, opp.score, opp.confidence)


def build_universe(client: TabdealPublicClient, max_symbols: int = DEFAULT_MAX_SYMBOLS) -> list[str]:
    """Dynamic universe from exchangeInfo; prefer priority symbols."""
    symbols: list[str] = []
    try:
        info = None
        if hasattr(client, "_get"):
            try:
                info = client._get("/r/fapi/v1/exchangeInfo")  # type: ignore[attr-defined]
            except Exception:
                info = None
        if not info:
            info = client.exchange_info()
        symbols = extract_symbols(info, quote_asset="USDT")
    except Exception as exc:
        logger.warning("exchangeInfo failed: %s — using priority fallback", exc)
    if not symbols:
        symbols = list(PRIORITY_SYMBOLS)
    ordered: list[str] = []
    for p in PRIORITY_SYMBOLS:
        if p in symbols and p not in ordered:
            ordered.append(p)
    for s in symbols:
        if s not in ordered:
            ordered.append(s)
        if len(ordered) >= max_symbols:
            break
    return ordered[:max_symbols]


def _optional_higher_tf_note(
    client: TabdealPublicClient, symbol: str, side: str, capital: float, risk_percent: float
) -> str:
    """Best-effort 1h confirmation using existing scan_symbol. No invented candles."""
    try:
        sig = scan_symbol(client, symbol, "1h", capital, risk_percent)
        if sig.direction == "NO_TRADE":
            return "1h:INSUFFICIENT_OR_NO_SETUP"
        if sig.direction.upper() == side.upper():
            return f"1h:ALIGN score={sig.score}"
        return f"1h:CONFLICT {sig.direction}"
    except Exception:
        return "1h:UNAVAILABLE"


def _try_notify(opp: CloudOpportunity) -> None:
    """Best-effort FCM. Never raises into scan loop. Never places orders."""
    if opp.score < MIN_SCORE:
        return
    if not opportunity_store.should_notify(opp.fingerprint):
        return
    try:
        from scanner.fcm_dispatcher import dispatch_opportunity

        result = dispatch_opportunity(opp)
        if result.get("sent", 0) > 0:
            opportunity_store.mark_notified(opp.fingerprint)
            opportunity_store.notifications_sent += int(result["sent"])
    except Exception as exc:
        logger.debug("notify failed: %s", exc)


def run_scan_once(
    client: TabdealPublicClient | None = None,
    *,
    timeframe: str = DEFAULT_TIMEFRAME,
    capital: float = DEFAULT_CAPITAL,
    risk_percent: float = DEFAULT_RISK_PCT,
    max_symbols: int = DEFAULT_MAX_SYMBOLS,
    min_score: float = MIN_SCORE,
) -> dict[str, Any]:
    """One scan cycle. Reuses existing scan_symbol. Never invents data. Never orders."""
    client = client or TabdealPublicClient()
    hints = _tv_hints()
    opportunity_store.expire_stale()
    universe = build_universe(client, max_symbols=max_symbols)
    found: list[CloudOpportunity] = []
    errors = 0

    for symbol in universe:
        try:
            signal = scan_symbol(client, symbol, timeframe, capital, risk_percent)
            if signal.direction == "NO_TRADE":
                continue
            if signal.score < min_score:
                continue
            side = signal.direction.upper()
            if side not in ("LONG", "SHORT"):
                continue

            hint_side = hints.get(symbol.upper())
            tv_agree = hint_side == side
            if hint_side and hint_side != side:
                conf = min(70.0, float(signal.score) * 0.85)
                reasons = list(signal.reasons) if signal.reasons else []
                reasons.append(f"TV conflict:{hint_side}")
            else:
                conf = min(99.0, max(0.0, float(signal.score)))
                reasons = list(signal.reasons) if signal.reasons else []

            regime = "UNKNOWN"
            if signal.score >= 80 and side == "LONG":
                regime = "TRENDING_BULL"
            elif signal.score >= 80 and side == "SHORT":
                regime = "TRENDING_BEAR"
            elif signal.score < 75:
                regime = "RANGING"

            higher = _optional_higher_tf_note(client, symbol, side, capital, risk_percent)
            if "CONFLICT" in higher:
                conf = min(conf, conf * 0.9)
                reasons.append(higher)
            elif "ALIGN" in higher:
                reasons.append(higher)
                conf = min(99.0, conf + 2)
            elif "UNAVAILABLE" in higher or "INSUFFICIENT" in higher:
                reasons.append(higher)

            tps = list(signal.take_profit) if signal.take_profit else []
            now = _now_ms()
            opp = CloudOpportunity(
                symbol=symbol.upper(),
                side=side,
                timeframe=timeframe,
                entry=float(signal.entry),
                stop_loss=float(signal.stop_loss),
                take_profit=[float(x) for x in tps],
                score=float(signal.score),
                confidence=conf,
                regime=regime,
                data_health="LIVE",
                reasons=reasons,
                source="scanner+tv" if tv_agree else "scanner",
                tv_agree=tv_agree,
                fingerprint=_fingerprint(symbol, side, timeframe, float(signal.entry)),
                status="VALIDATED",
                created_at_ms=now,
                updated_at_ms=now,
                higher_tf=higher,
            )
            found.append(opp)
        except Exception as exc:
            errors += 1
            logger.debug("scan %s failed: %s", symbol, exc)
            continue

    found.sort(key=lambda o: _rank_key(o, hints), reverse=True)
    accepted = 0
    for opp in found:
        ok, _ = opportunity_store.upsert(opp)
        if ok:
            accepted += 1

    notified = 0
    for opp in found[:3]:
        before = opportunity_store.notifications_sent
        _try_notify(opp)
        if opportunity_store.notifications_sent > before:
            notified += 1

    now = _now_ms()
    opportunity_store.last_scan_at_ms = now
    opportunity_store.last_success_at_ms = now
    opportunity_store.last_error = ""
    opportunity_store.last_scanned_count = len(universe)
    opportunity_store.last_opportunity_count = accepted
    detail = (
        f"scanned={len(universe)} found={len(found)} accepted={accepted} "
        f"errors={errors} tv_hints={len(hints)} notified={notified}"
    )
    if accepted == 0:
        detail += " | NO VALID OPPORTUNITY"
    opportunity_store.last_scan_detail = detail
    logger.info("cloud scan: %s", detail)
    return {
        "scanned": len(universe),
        "found": len(found),
        "accepted": accepted,
        "errors": errors,
        "tv_hints": len(hints),
        "notified": notified,
        "detail": detail,
        "top": [o.to_dict() for o in found[:5]],
    }


class MarketWorker:
    """Background loop. Stops cleanly. No orders. No direct Tabdeal private calls."""

    def __init__(
        self,
        interval_sec: int = DEFAULT_INTERVAL_SEC,
        client: TabdealPublicClient | None = None,
    ) -> None:
        self.interval_sec = max(30, interval_sec)
        self.client = client or TabdealPublicClient()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        opportunity_store.worker_running = True
        if not opportunity_store.started_at_ms:
            opportunity_store.started_at_ms = _now_ms()
        self._thread = threading.Thread(
            target=self._loop, name="signalyab-cloud-worker", daemon=True
        )
        self._thread.start()
        logger.info("MarketWorker started interval=%ss", self.interval_sec)

    def stop(self) -> None:
        self._stop.set()
        opportunity_store.worker_running = False
        t = self._thread
        if t and t.is_alive():
            t.join(timeout=5)
        logger.info("MarketWorker stopped")

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                run_scan_once(self.client)
            except Exception as exc:
                opportunity_store.last_scan_detail = f"scan error: {exc}"
                opportunity_store.last_error = str(exc)
                logger.exception("cloud worker scan failed")
            self._stop.wait(self.interval_sec)


_worker: MarketWorker | None = None


def start_worker_if_enabled() -> bool:
    """Start only when CLOUD_WORKER_ENABLED=true."""
    global _worker
    enabled = os.getenv("CLOUD_WORKER_ENABLED", "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )
    if not enabled:
        logger.info(
            "CLOUD_WORKER_ENABLED not set — worker not started (Flutter poll remains available)"
        )
        return False
    if _worker is None:
        _worker = MarketWorker()
    _worker.start()
    return True


def stop_worker() -> None:
    global _worker
    if _worker is not None:
        _worker.stop()
        _worker = None
