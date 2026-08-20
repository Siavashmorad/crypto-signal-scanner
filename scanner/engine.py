from __future__ import annotations

from dataclasses import asdict

from analysis.candles import build_candles
from analysis.indicators import atr, ema, macd_histogram, rsi, volume_ratio
from analysis.risk_engine import RiskSetup, valid_setup
from analysis.signal import Signal, no_trade
from data.tabdeal import TabdealPublicClient

TIMEFRAME_SECONDS = {"1m": 60, "5m": 300, "15m": 900, "1h": 3600}


def _orderbook_score(
    bids: tuple[tuple[float, float], ...],
    asks: tuple[tuple[float, float], ...],
) -> float:
    bid_volume = sum(q for _, q in bids)
    ask_volume = sum(q for _, q in asks)
    total = bid_volume + ask_volume
    if total <= 0:
        return 50.0
    return max(0.0, min(100.0, 50 + 50 * (bid_volume - ask_volume) / total))


def scan_symbol(
    client: TabdealPublicClient,
    symbol: str,
    timeframe: str,
    capital: float,
    risk_percent: float = 1.0,
) -> Signal:
    """Generate a signal from real Tabdeal market data; never places an order."""
    if timeframe not in TIMEFRAME_SECONDS:
        return no_trade(symbol, timeframe, "unsupported timeframe")

    trades = client.trades(symbol, limit=1000)
    candles = build_candles(trades, TIMEFRAME_SECONDS[timeframe])
    if len(candles) < 40:
        return no_trade(symbol, timeframe, "not enough market history")

    closes = [c.close for c in candles]
    highs = [c.high for c in candles]
    lows = [c.low for c in candles]
    volumes = [c.volume for c in candles]

    fast = ema(closes, 9)
    slow = ema(closes, 21)
    momentum = rsi(closes, 14)
    hist = macd_histogram(closes)
    vol_r = volume_ratio(volumes)
    volatility = atr(highs, lows, closes, 14)

    if fast is None or slow is None or momentum is None:
        return no_trade(symbol, timeframe, "indicators unavailable")

    book = client.depth(symbol, limit=50)
    ob_score = _orderbook_score(book.bids, book.asks)
    imbalance = (ob_score - 50) / 50

    trend_score = 82.0 if fast > slow else 18.0
    if fast > slow and closes[-1] > closes[-5]:
        trend_score = 90.0
    if fast < slow and closes[-1] < closes[-5]:
        trend_score = 10.0

    momentum_score = max(0.0, min(100.0, momentum))
    if momentum > 75 or momentum < 25:
        momentum_score *= 0.72

    macd_score = 50.0
    if hist is not None:
        macd_score = max(
            0.0,
            min(100.0, 50 + hist / (abs(closes[-1]) * 0.001 + 1e-9) * 8),
        )

    vol_score = max(15.0, min(95.0, 50 + (vol_r - 1.0) * 40))
    score = round(
        trend_score * 0.30
        + momentum_score * 0.25
        + ob_score * 0.22
        + macd_score * 0.13
        + vol_score * 0.10,
        2,
    )

    if score < 66:
        return no_trade(symbol, timeframe, f"signal score {score} below threshold")

    long_votes = 0
    short_votes = 0
    reasons: list[str] = []

    if fast > slow:
        long_votes += 1
        reasons.append("EMA 9/21 bullish trend")
    else:
        short_votes += 1
        reasons.append("EMA 9/21 bearish trend")

    if momentum >= 52:
        long_votes += 1
        if momentum > 55:
            reasons.append("positive RSI momentum")
    elif momentum <= 48:
        short_votes += 1
        if momentum < 45:
            reasons.append("negative RSI momentum")

    if imbalance >= 0.06:
        long_votes += 1
        reasons.append("buy pressure in order book")
    elif imbalance <= -0.06:
        short_votes += 1
        reasons.append("sell pressure in order book")

    if hist is not None:
        if hist > 0:
            long_votes += 1
            reasons.append("positive MACD histogram")
        elif hist < 0:
            short_votes += 1
            reasons.append("negative MACD histogram")

    if vol_r > 1.12:
        reasons.append("rising trading volume")

    if long_votes >= 3 and long_votes > short_votes:
        direction = "LONG"
    elif short_votes >= 3 and short_votes > long_votes:
        direction = "SHORT"
    else:
        return no_trade(symbol, timeframe, "insufficient indicator confluence")

    entry = closes[-1]
    if volatility and volatility > 0:
        risk_dist = volatility * 1.25
    else:
        recent_low = min(c.low for c in candles[-12:])
        recent_high = max(c.high for c in candles[-12:])
        risk_dist = max((recent_high - recent_low) * 0.45, entry * 0.006)

    if direction == "LONG":
        stop = entry - risk_dist
        tp1 = entry + risk_dist * 1.8
        tp2 = entry + risk_dist * 3.0
    else:
        stop = entry + risk_dist
        tp1 = entry - risk_dist * 1.8
        tp2 = entry - risk_dist * 3.0

    if risk_dist <= 0:
        return no_trade(symbol, timeframe, "invalid stop distance")

    setup = RiskSetup(entry, stop, tp1, capital, risk_percent)
    if not valid_setup(setup, minimum_reward_risk=1.6):
        return no_trade(symbol, timeframe, "risk/reward constraints not satisfied")

    return Signal(
        symbol=symbol,
        direction=direction,
        timeframe=timeframe,
        entry=entry,
        stop_loss=stop,
        take_profit=(tp1, tp2),
        score=score,
        reasons=tuple(reasons[:5]),
    )


def signal_to_dict(signal: Signal) -> dict:
    return asdict(signal)
