from __future__ import annotations

from dataclasses import dataclass

from data.tabdeal import Trade


@dataclass(frozen=True)
class Candle:
    start_ms: int
    open: float
    high: float
    low: float
    close: float
    volume: float
    trades: int


def build_candles(trades: list[Trade], interval_seconds: int) -> list[Candle]:
    if interval_seconds <= 0:
        raise ValueError("interval_seconds must be positive")
    buckets: dict[int, list[Trade]] = {}
    width = interval_seconds * 1000
    for trade in sorted(trades, key=lambda x: x.timestamp_ms):
        start = (trade.timestamp_ms // width) * width
        buckets.setdefault(start, []).append(trade)
    candles: list[Candle] = []
    for start, rows in sorted(buckets.items()):
        prices = [row.price for row in rows]
        candles.append(Candle(start, prices[0], max(prices), min(prices), prices[-1], sum(row.quantity for row in rows), len(rows)))
    return candles
