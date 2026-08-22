"""Tabdeal TRADE client — only used after explicit user approval."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class TabdealTradeError(RuntimeError):
    pass


class TabdealTradeClient:
    """Signed requests for Tabdeal order endpoints."""

    def __init__(
        self,
        api_key: str | None = None,
        api_secret: str | None = None,
        base_url: str = "https://api1.tabdeal.org",
        timeout: float = 12.0,
    ) -> None:
        self.api_key = api_key or os.getenv("TABDEAL_API_KEY", "")
        self.api_secret = api_secret or os.getenv("TABDEAL_API_SECRET", "")
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    @property
    def configured(self) -> bool:
        return bool(self.api_key and self.api_secret)

    def _sign(self, params: dict[str, Any]) -> dict[str, Any]:
        payload = dict(params)
        payload["timestamp"] = int(time.time() * 1000)
        query = urllib.parse.urlencode(payload, doseq=True)
        signature = hmac.new(
            self.api_secret.encode("utf-8"),
            query.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()
        payload["signature"] = signature
        return payload

    def _request(self, method: str, path: str, params: dict[str, Any]) -> Any:
        if not self.configured:
            raise TabdealTradeError("TABDEAL_API_KEY / TABDEAL_API_SECRET not configured")
        signed = self._sign(params)
        query = urllib.parse.urlencode(signed, doseq=True)
        url = f"{self.base_url}{path}"
        headers = {
            "X-MBX-APIKEY": self.api_key,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
            "User-Agent": "crypto-signal-scanner/execution",
        }
        if method.upper() == "GET":
            req = urllib.request.Request(f"{url}?{query}", headers=headers, method="GET")
        else:
            req = urllib.request.Request(
                url,
                data=query.encode("utf-8"),
                headers=headers,
                method=method.upper(),
            )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as response:
                body = response.read().decode("utf-8")
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise TabdealTradeError(f"Tabdeal TRADE HTTP {exc.code}: {detail}") from exc
        except Exception as exc:
            raise TabdealTradeError(f"Tabdeal TRADE request failed: {exc}") from exc

    def place_market_order(self, symbol: str, side: str, quantity: float) -> dict[str, Any]:
        """side: BUY or SELL. quantity > 0."""
        if quantity <= 0:
            raise TabdealTradeError("quantity must be positive")
        side_u = side.upper()
        if side_u not in {"BUY", "SELL"}:
            raise TabdealTradeError("side must be BUY or SELL")
        return self._request(
            "POST",
            "/api/v1/order",
            {
                "symbol": symbol.upper(),
                "side": side_u,
                "type": "MARKET",
                "quantity": f"{quantity:.8f}".rstrip("0").rstrip(".") or "0",
            },
        )
