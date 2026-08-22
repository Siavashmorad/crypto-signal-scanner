"""Live mark-price monitoring and unrealized PnL for open positions."""
from __future__ import annotations

import time
from typing import Any

from data.tabdeal import TabdealPublicClient, TabdealAPIError
from execution import store
from execution import service as execution_service
from execution.models import ActionStatus, ActionType


def _mid_price(client: TabdealPublicClient, symbol: str) -> float:
    book = client.depth(symbol, limit=5)
    bid = book.bids[0][0] if book.bids else None
    ask = book.asks[0][0] if book.asks else None
    if bid is not None and ask is not None:
        return (bid + ask) / 2.0
    trades = client.trades(symbol, limit=5)
    if not trades:
        raise TabdealAPIError(f"no price for {symbol}")
    return trades[-1].price


def _unrealized_pnl(side: str, entry: float, mark: float, quantity: float) -> float:
    if entry <= 0 or quantity <= 0:
        return 0.0
    if side.upper() == "LONG":
        return (mark - entry) * quantity
    return (entry - mark) * quantity


def _pnl_percent(side: str, entry: float, mark: float) -> float:
    if entry <= 0:
        return 0.0
    if side.upper() == "LONG":
        return ((mark - entry) / entry) * 100.0
    return ((entry - mark) / entry) * 100.0


def _hit_take_profit(side: str, mark: float, tp: float | None) -> bool:
    if tp is None or tp <= 0:
        return False
    if side.upper() == "LONG":
        return mark >= tp
    return mark <= tp


def _hit_stop_loss(side: str, mark: float, sl: float | None) -> bool:
    if sl is None or sl <= 0:
        return False
    if side.upper() == "LONG":
        return mark <= sl
    return mark >= sl


def _already_pending_close(symbol: str) -> bool:
    for action in store.list_pending(only_open=True):
        if action.symbol == symbol.upper() and action.action == ActionType.CLOSE:
            return True
    return False


def snapshot_positions(
    client: TabdealPublicClient | None = None,
    *,
    auto_propose_close: bool = True,
) -> dict[str, Any]:
    """Refresh mark price + PnL; optionally queue CLOSE for user approval on TP/SL."""
    client = client or TabdealPublicClient()
    rows: list[dict[str, Any]] = []
    proposed: list[dict[str, Any]] = []
    now = int(time.time() * 1000)

    for pos in store.get_paper_positions():
        symbol = str(pos.get("symbol", "")).upper()
        side = str(pos.get("side", "LONG")).upper()
        quantity = float(pos.get("quantity") or 0)
        entry = float(pos.get("entry") or 0)
        stop_loss = pos.get("stop_loss")
        take_profit = pos.get("take_profit")
        sl = float(stop_loss) if stop_loss is not None else None
        tp = float(take_profit) if take_profit is not None else None

        try:
            mark = _mid_price(client, symbol)
            err = None
        except Exception as exc:  # noqa: BLE001
            mark = entry
            err = str(exc)

        pnl = _unrealized_pnl(side, entry, mark, quantity)
        pnl_pct = _pnl_percent(side, entry, mark)
        tp_hit = _hit_take_profit(side, mark, tp)
        sl_hit = _hit_stop_loss(side, mark, sl)

        row = {
            **pos,
            "symbol": symbol,
            "side": side,
            "quantity": quantity,
            "entry": entry,
            "mark_price": mark,
            "unrealized_pnl": round(pnl, 8),
            "unrealized_pnl_percent": round(pnl_pct, 4),
            "take_profit_hit": tp_hit,
            "stop_loss_hit": sl_hit,
            "checked_at_ms": now,
            "price_error": err,
        }
        rows.append(row)

        # Persist refreshed mark for UI consistency
        updated = dict(pos)
        updated.update(
            {
                "mark_price": mark,
                "unrealized_pnl": row["unrealized_pnl"],
                "unrealized_pnl_percent": row["unrealized_pnl_percent"],
                "last_check_ms": now,
            }
        )
        store.set_paper_position(symbol, updated)

        if auto_propose_close and (tp_hit or sl_hit) and not _already_pending_close(symbol):
            reason = "TP hit" if tp_hit else "SL hit"
            try:
                action = execution_service.propose_close(
                    symbol=symbol,
                    quantity=quantity,
                    reason=f"auto monitor: {reason} @ mark={mark}",
                )
                proposed.append(action.to_dict())
            except Exception as exc:  # noqa: BLE001
                row["propose_error"] = str(exc)

    total_pnl = sum(float(r.get("unrealized_pnl") or 0) for r in rows)
    return {
        "positions": rows,
        "count": len(rows),
        "total_unrealized_pnl": round(total_pnl, 8),
        "auto_close_proposals": proposed,
        "checked_at_ms": now,
    }
