"""In-memory pending actions + paper positions (process-local)."""
from __future__ import annotations

from threading import Lock
from typing import Any

from execution.models import ActionStatus, PendingAction

_lock = Lock()
_pending: dict[str, PendingAction] = {}
_paper_positions: dict[str, dict[str, Any]] = {}


def add_pending(action: PendingAction) -> PendingAction:
    with _lock:
        _pending[action.id] = action
        return action


def get_pending(action_id: str) -> PendingAction | None:
    with _lock:
        return _pending.get(action_id)


def list_pending(only_open: bool = True) -> list[PendingAction]:
    with _lock:
        rows = list(_pending.values())
    if only_open:
        rows = [a for a in rows if a.status == ActionStatus.PENDING]
    rows.sort(key=lambda a: a.created_at_ms, reverse=True)
    return rows


def update_pending(action: PendingAction) -> None:
    with _lock:
        _pending[action.id] = action


def set_paper_position(symbol: str, position: dict[str, Any] | None) -> None:
    with _lock:
        if position is None:
            _paper_positions.pop(symbol, None)
        else:
            _paper_positions[symbol] = position


def get_paper_positions() -> list[dict[str, Any]]:
    with _lock:
        return list(_paper_positions.values())


def get_paper_position(symbol: str) -> dict[str, Any] | None:
    with _lock:
        return _paper_positions.get(symbol)
