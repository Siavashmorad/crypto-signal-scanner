from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

BASE_URL = "https://api1.tabdeal.org"


class TabdealAPIError(RuntimeError):
    pass


@dataclass(frozen=True)
class Trade:
    price: float
    quantity: float
    timestamp_ms: int


@dataclass(frozen=True)
class OrderBook:
    bids: tuple[tuple[float, float], ...]
    asks: tuple[tuple[float, float], ...]
    timestamp_ms: int


class TabdealPublicClient:
    """Public market-data client. It intentionally has no order endpoints."""

    def __init__(self, base_url: str = BASE_URL, timeout: float = 8.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def _get(self, path: str, params: dict[str, Any] | None = None) -> Any:
        query = urllib.parse.urlencode({k: v for k, v in (params or {}).items() if v is not None})
        url = f"{self.base_url}{path}" + (f"?{query}" if query else "")
        request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "crypto-signal-scanner/1.0"})
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            raise TabdealAPIError(f"Tabdeal request failed: {path}: {exc}") from exc

    def ping(self) -> Any:
        return self._get("/r/api/v1/ping")

    def time(self) -> Any:
        return self._get("/r/api/v1/time")

    def exchange_info(self) -> Any:
        return self._get("/r/api/v1/exchangeInfo")

    def trades(self, symbol: str, limit: int = 1000) -> list[Trade]:
        payload = self._get("/r/api/v1/trades", {"symbol": symbol, "limit": limit})
        if not isinstance(payload, list):
            raise TabdealAPIError("Unexpected trades response")
        result: list[Trade] = []
        now = int(time.time() * 1000)
        for item in payload:
            if isinstance(item, (list, tuple)) and len(item) >= 3:
                price, quantity, timestamp = item[:3]
            elif isinstance(item, dict):
                price = item.get("price")
                quantity = item.get("qty", item.get("quantity"))
                timestamp = item.get("time", item.get("timestamp", now))
            else:
                continue
            if price is None or quantity is None:
                continue
            result.append(Trade(float(price), float(quantity), int(timestamp)))
        return result

    def depth(self, symbol: str, limit: int = 50) -> OrderBook:
        payload = self._get("/r/api/v1/depth", {"symbol": symbol, "limit": limit})
        if not isinstance(payload, dict):
            raise TabdealAPIError("Unexpected depth response")
        bids = tuple((float(row[0]), float(row[1])) for row in payload.get("bids", []) if len(row) >= 2)
        asks = tuple((float(row[0]), float(row[1])) for row in payload.get("asks", []) if len(row) >= 2)
        return OrderBook(bids=bids, asks=asks, timestamp_ms=int(time.time() * 1000))
