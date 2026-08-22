"""Hard risk limits for real-money operation."""
from __future__ import annotations

import os
from typing import Any

from execution import store


def _f(name: str, default: float) -> float:
    raw = os.getenv(name, "").strip()
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def limits() -> dict[str, Any]:
    return {
        "max_open_positions": int(_f("MAX_OPEN_POSITIONS", 3)),
        "max_position_notional_usdt": _f("MAX_POSITION_NOTIONAL_USDT", 50.0),
        "max_risk_percent_per_trade": _f("MAX_RISK_PERCENT_PER_TRADE", 1.0),
        "max_daily_loss_usdt": _f("MAX_DAILY_LOSS_USDT", 30.0),
    }


def validate_open(
    *,
    symbol: str,
    quantity: float,
    entry: float | None,
    capital_usdt: float | None = None,
) -> None:
    cfg = limits()
    open_count = len(store.get_paper_positions())
    if open_count >= cfg["max_open_positions"]:
        raise RuntimeError(
            f"max open positions reached ({cfg['max_open_positions']})"
        )
    if entry and entry > 0 and quantity > 0:
        notional = entry * quantity
        if notional > cfg["max_position_notional_usdt"]:
            raise RuntimeError(
                f"position notional {notional:.4f} exceeds max "
                f"{cfg['max_position_notional_usdt']} USDT"
            )
