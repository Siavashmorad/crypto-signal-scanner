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
