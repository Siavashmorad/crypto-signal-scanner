"""In-memory FCM device token registry (process lifetime).

No secrets stored. Tokens are device push endpoints only.
"""

from __future__ import annotations

import threading
import time
from dataclasses import asdict, dataclass
from typing import Any


def _now_ms() -> int:
    return int(time.time() * 1000)


@dataclass
class DeviceRecord:
    device_id: str
    fcm_token: str
    platform: str  # android | ios
    enabled: bool
    updated_at_ms: int
    app_version: str = ""

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        tok = self.fcm_token or ""
        d["fcm_token_tail"] = tok[-8:] if len(tok) >= 8 else "***"
        del d["fcm_token"]
        return d


class DeviceRegistry:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._by_id: dict[str, DeviceRecord] = {}
        self._by_token: dict[str, str] = {}  # token -> device_id

    def register(
        self,
        *,
        device_id: str,
        fcm_token: str,
        platform: str = "android",
        enabled: bool = True,
        app_version: str = "",
    ) -> DeviceRecord:
        device_id = (device_id or "").strip()[:128]
        fcm_token = (fcm_token or "").strip()
        platform = (platform or "android").strip().lower()[:16]
        app_version = (app_version or "").strip()[:32]
        if not device_id or not fcm_token or len(fcm_token) < 20:
            raise ValueError("device_id and valid fcm_token required")
        now = _now_ms()
        with self._lock:
            old_id = self._by_token.get(fcm_token)
            if old_id and old_id != device_id and old_id in self._by_id:
                prev = self._by_id[old_id]
                if prev.fcm_token == fcm_token:
                    del self._by_id[old_id]
            rec = DeviceRecord(
                device_id=device_id,
                fcm_token=fcm_token,
                platform=platform,
                enabled=bool(enabled),
                updated_at_ms=now,
                app_version=app_version,
            )
            self._by_id[device_id] = rec
            self._by_token[fcm_token] = device_id
            return rec

    def disable(self, device_id: str) -> bool:
        with self._lock:
            rec = self._by_id.get(device_id)
            if not rec:
                return False
            rec.enabled = False
            rec.updated_at_ms = _now_ms()
            return True

    def remove(self, device_id: str) -> bool:
        with self._lock:
            rec = self._by_id.pop(device_id, None)
            if not rec:
                return False
            if self._by_token.get(rec.fcm_token) == device_id:
                del self._by_token[rec.fcm_token]
            return True

    def enabled_tokens(self) -> list[str]:
        with self._lock:
            return [r.fcm_token for r in self._by_id.values() if r.enabled and r.fcm_token]

    def list_devices(self) -> list[dict[str, Any]]:
        with self._lock:
            return [r.to_dict() for r in self._by_id.values()]

    def count_enabled(self) -> int:
        with self._lock:
            return sum(1 for r in self._by_id.values() if r.enabled)

    def health(self) -> dict[str, Any]:
        with self._lock:
            total = len(self._by_id)
            enabled = sum(1 for r in self._by_id.values() if r.enabled)
        return {"devices_total": total, "devices_enabled": enabled}


device_registry = DeviceRegistry()
