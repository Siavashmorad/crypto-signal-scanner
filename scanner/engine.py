from __future__ import annotations

from dataclasses import asdict

from analysis.candles import build_candles
from analysis.indicators import ema, rsi
from analysis.risk_engine import RiskSetup, valid_setup
from analysis.signal import Signal, no_trade
from data.tabdeal import TabdealPublicClient

TIMEFRAME_SECONDS = {"1m": 60, "5m": 300, "15m": 900, "1h": 3600}


def _orderbook_score(bids: tuple[tuple[float, float], ...], asks: tuple[tuple[float, float], ...]) -> float:
    bid_volume = sum(q for _, q in bids)
    ask_volume = sum(q for _, q in asks)
    total = bid_volume + ask_volume
    if total <= 0:
        return 50.0
    return max(0.0, min(100.0, 50 + 50 * (bid_volume - ask_volume) / total))


def scan_symbol(client: TabdealPublicClient, symbol: str, timeframe: str, capital: float, risk_percent: float = 1.0) -> Signal:
    if timeframe not in TIMEFRAME_SECONDS:
        return no_trade(symbol, timeframe, "unsupported timeframe")
    trades = client.trades(symbol, limit=1000)
    candles = build_candles(trades, TIMEFRAME_SECONDS[timeframe])
    if len(candles) < 20:
        return no_trade(symbol, timeframe, "not enough market history")

    closes = [c.close for c in candles]
    fast = ema(closes, 9)
    slow = ema(closes, 21)
    momentum = rsi(closes, 14)
    if fast is None or slow is None or momentum is None:
        return no_trade(symbol, timeframe, "indicators unavailable")

    book = client.depth(symbol, limit=50)
    ob_score = _orderbook_score(book.bids, book.asks)
    trend_score = 80.0 if fast > slow else 20.0
    momentum_score = max(0.0, min(100.0, momentum))
    score = round((trend_score + momentum_score + ob_score) / 3, 2)

    if score < 70:
        return no_trade(symbol, timeframe, f"signal score {score} below threshold")

    entry = closes[-1]
    recent_low = min(c.low for c in candles[-10:])
    recent_high = max(c.high for c in candles[-10:])
    direction = "LONG" if fast > slow and momentum >= 50 else "SHORT"
    if direction == "LONG":
        stop = recent_low
        risk = entry - stop
        target = entry + 2 * risk
    else:
        stop = recent_high
        risk = stop - entry
        target = entry - 2 * risk
    if risk <= 0:
        return no_trade(symbol, timeframe, "invalid stop distance")

    setup = RiskSetup(entry, stop, target, capital, risk_percent)
    if not valid_setup(setup):
        return no_trade(symbol, timeframe, "risk/reward constraints not satisfied")

    return Signal(symbol, direction, timeframe, entry, stop, (target,), score, ("EMA trend", "RSI momentum", "order book imbalance"))


def signal_to_dict(signal: Signal) -> dict:
    return asdict(signal)
