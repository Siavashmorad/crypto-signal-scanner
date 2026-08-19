from dataclasses import dataclass
from typing import Literal

Direction = Literal["LONG", "SHORT", "NO_TRADE"]


@dataclass(frozen=True)
class Signal:
    symbol: str
    direction: Direction
    timeframe: str
    entry: float | None
    stop_loss: float | None
    take_profit: tuple[float, ...]
    score: float
    reasons: tuple[str, ...]


def no_trade(symbol: str, timeframe: str, reason: str) -> Signal:
    return Signal(
        symbol=symbol,
        direction="NO_TRADE",
        timeframe=timeframe,
        entry=None,
        stop_loss=None,
        take_profit=(),
        score=0.0,
        reasons=(reason,),
    )
