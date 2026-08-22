from __future__ import annotations

from dataclasses import asdict, dataclass, field
from enum import Enum
from typing import Any
import time
import uuid


class ExecutionMode(str, Enum):
    SIGNAL_ONLY = "signal_only"
    PAPER = "paper"
    LIVE_WITH_APPROVAL = "live_with_approval"


class ActionType(str, Enum):
    OPEN = "OPEN"
    CLOSE = "CLOSE"


class ActionStatus(str, Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"
    EXECUTED = "EXECUTED"
    FAILED = "FAILED"
    EXPIRED = "EXPIRED"


@dataclass
class PendingAction:
    id: str
    action: ActionType
    symbol: str
    side: str  # LONG / SHORT for open; BUY/SELL mapped at execution
    quantity: float
    entry: float | None
    stop_loss: float | None
    take_profit: float | None
    reason: str
    status: ActionStatus = ActionStatus.PENDING
    created_at_ms: int = field(default_factory=lambda: int(time.time() * 1000))
    expires_at_ms: int = 0
    result: dict[str, Any] = field(default_factory=dict)
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["action"] = self.action.value
        data["status"] = self.status.value
        return data


def new_action_id() -> str:
    return uuid.uuid4().hex[:12]
