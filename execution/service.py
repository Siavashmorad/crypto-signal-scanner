"""Propose → approve/reject → execute (paper or live)."""
from __future__ import annotations

import os
import time
from typing import Any

from execution.models import (
    ActionStatus,
    ActionType,
    ExecutionMode,
    PendingAction,
    new_action_id,
)
from execution import store
from execution import risk
from execution.tabdeal_trade import TabdealTradeClient, TabdealTradeError

DEFAULT_TTL_MS = 15 * 60 * 1000  # 15 minutes


def current_mode() -> ExecutionMode:
    raw = os.getenv("EXECUTION_MODE", "signal_only").strip().lower()
    try:
        return ExecutionMode(raw)
    except ValueError:
        return ExecutionMode.SIGNAL_ONLY


def mode_info() -> dict[str, Any]:
    mode = current_mode()
    trade = TabdealTradeClient()
    return {
        "mode": mode.value,
        "live_keys_configured": trade.configured,
        "can_propose": mode != ExecutionMode.SIGNAL_ONLY,
        "can_live_execute": mode == ExecutionMode.LIVE_WITH_APPROVAL and trade.configured,
        "risk": risk.limits(),
        "note": {
            ExecutionMode.SIGNAL_ONLY.value: "فقط سیگنال؛ هیچ سفارشی ارسال نمی‌شود",
            ExecutionMode.PAPER.value: "پوزیشن مجازی بعد از تأیید شما",
            ExecutionMode.LIVE_WITH_APPROVAL.value: "سفارش واقعی تبدیل فقط بعد از تأیید صریح شما",
        }.get(mode.value, ""),
        "business": {
            "market_data": "Tabdeal public API (real-time)",
            "orders": "Tabdeal TRADE API when mode=live_with_approval",
            "ai": "OpenAI via private backend (OPENAI_API_KEY)",
            "approval": "required before every open and close",
            "pnl": "mark price from live order book",
        },
    }


def propose_open(
    *,
    symbol: str,
    side: str,
    quantity: float,
    entry: float | None = None,
    stop_loss: float | None = None,
    take_profit: float | None = None,
    reason: str = "user requested open",
    ttl_ms: int = DEFAULT_TTL_MS,
) -> PendingAction:
    mode = current_mode()
    if mode == ExecutionMode.SIGNAL_ONLY:
        raise RuntimeError("EXECUTION_MODE=signal_only — set paper or live_with_approval")
    side_u = side.upper()
    if side_u not in {"LONG", "SHORT"}:
        raise ValueError("side must be LONG or SHORT")
    if quantity <= 0:
        raise ValueError("quantity must be positive")
    risk.validate_open(symbol=symbol, quantity=quantity, entry=entry)
    now = int(time.time() * 1000)
    action = PendingAction(
        id=new_action_id(),
        action=ActionType.OPEN,
        symbol=symbol.upper(),
        side=side_u,
        quantity=quantity,
        entry=entry,
        stop_loss=stop_loss,
        take_profit=take_profit,
        reason=reason,
        created_at_ms=now,
        expires_at_ms=now + ttl_ms,
    )
    return store.add_pending(action)


def propose_close(
    *,
    symbol: str,
    quantity: float | None = None,
    reason: str = "user requested close",
    ttl_ms: int = DEFAULT_TTL_MS,
) -> PendingAction:
    mode = current_mode()
    if mode == ExecutionMode.SIGNAL_ONLY:
        raise RuntimeError("EXECUTION_MODE=signal_only — set paper or live_with_approval")
    symbol_u = symbol.upper()
    qty = quantity
    if qty is None:
        paper = store.get_paper_position(symbol_u)
        qty = float(paper.get("quantity", 0)) if paper else 0.0
    if qty is not None and qty <= 0:
        raise ValueError("no open quantity to close")
    now = int(time.time() * 1000)
    side = "CLOSE"
    paper = store.get_paper_position(symbol_u)
    if paper:
        side = paper.get("side", "LONG")
    action = PendingAction(
        id=new_action_id(),
        action=ActionType.CLOSE,
        symbol=symbol_u,
        side=str(side),
        quantity=float(qty or 0),
        entry=None,
        stop_loss=None,
        take_profit=None,
        reason=reason,
        created_at_ms=now,
        expires_at_ms=now + ttl_ms,
    )
    return store.add_pending(action)


def reject(action_id: str) -> PendingAction:
    action = store.get_pending(action_id)
    if action is None:
        raise KeyError("action not found")
    if action.status != ActionStatus.PENDING:
        raise RuntimeError(f"action is {action.status.value}, cannot reject")
    action.status = ActionStatus.REJECTED
    store.update_pending(action)
    return action


def approve(action_id: str) -> PendingAction:
    """User explicit approval — only then execute paper or live order."""
    action = store.get_pending(action_id)
    if action is None:
        raise KeyError("action not found")
    if action.status != ActionStatus.PENDING:
        raise RuntimeError(f"action is {action.status.value}, cannot approve")
    now = int(time.time() * 1000)
    if action.expires_at_ms and now > action.expires_at_ms:
        action.status = ActionStatus.EXPIRED
        store.update_pending(action)
        raise RuntimeError("action expired — propose again")

    action.status = ActionStatus.APPROVED
    store.update_pending(action)

    mode = current_mode()
    try:
        if mode == ExecutionMode.PAPER:
            result = _execute_paper(action)
        elif mode == ExecutionMode.LIVE_WITH_APPROVAL:
            result = _execute_live(action)
        else:
            raise RuntimeError("execution disabled in signal_only mode")
        action.status = ActionStatus.EXECUTED
        action.result = result
        action.error = None
    except Exception as exc:
        action.status = ActionStatus.FAILED
        action.error = str(exc)
        action.result = {}
        store.update_pending(action)
        raise
    store.update_pending(action)
    return action


def _execute_paper(action: PendingAction) -> dict[str, Any]:
    now = int(time.time() * 1000)
    if action.action == ActionType.OPEN:
        pos = {
            "symbol": action.symbol,
            "side": action.side,
            "quantity": action.quantity,
            "entry": action.entry,
            "stop_loss": action.stop_loss,
            "take_profit": action.take_profit,
            "opened_at_ms": now,
            "mode": "paper",
        }
        store.set_paper_position(action.symbol, pos)
        return {"type": "paper_open", "position": pos}
    existing = store.get_paper_position(action.symbol)
    store.set_paper_position(action.symbol, None)
    return {"type": "paper_close", "closed": existing}


def _order_side_for_open(position_side: str) -> str:
    return "BUY" if position_side.upper() == "LONG" else "SELL"


def _order_side_for_close(position_side: str) -> str:
    return "SELL" if position_side.upper() == "LONG" else "BUY"


def _execute_live(action: PendingAction) -> dict[str, Any]:
    client = TabdealTradeClient()
    if not client.configured:
        raise TabdealTradeError("Live keys missing: set TABDEAL_API_KEY and TABDEAL_API_SECRET")

    if action.action == ActionType.OPEN:
        order_side = _order_side_for_open(action.side)
        raw = client.place_market_order(action.symbol, order_side, action.quantity)
        fill_entry = action.entry
        # Prefer exchange average fill if present
        if isinstance(raw, dict):
            for key in ("avgPrice", "price", "fills"):
                if key == "fills" and isinstance(raw.get("fills"), list) and raw["fills"]:
                    try:
                        fill_entry = float(raw["fills"][0].get("price") or fill_entry or 0)
                    except (TypeError, ValueError):
                        pass
                elif key in raw and raw[key] not in (None, ""):
                    try:
                        fill_entry = float(raw[key])
                    except (TypeError, ValueError):
                        pass
        store.set_paper_position(
            action.symbol,
            {
                "symbol": action.symbol,
                "side": action.side,
                "quantity": action.quantity,
                "entry": fill_entry,
                "stop_loss": action.stop_loss,
                "take_profit": action.take_profit,
                "opened_at_ms": int(time.time() * 1000),
                "mode": "live",
                "exchange": raw,
            },
        )
        return {"type": "live_open", "order": raw, "entry": fill_entry}

    pos = store.get_paper_position(action.symbol)
    position_side = (pos or {}).get("side", action.side)
    order_side = _order_side_for_close(str(position_side))
    qty = action.quantity or float((pos or {}).get("quantity") or 0)
    if qty <= 0:
        raise TabdealTradeError("no quantity to close")
    raw = client.place_market_order(action.symbol, order_side, qty)
    closed = pos
    store.set_paper_position(action.symbol, None)
    return {"type": "live_close", "order": raw, "closed": closed}
