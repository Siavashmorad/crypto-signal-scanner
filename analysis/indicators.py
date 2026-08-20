from __future__ import annotations


def ema(values: list[float], period: int) -> float | None:
    if period <= 0 or len(values) < period:
        return None
    alpha = 2 / (period + 1)
    result = sum(values[:period]) / period
    for value in values[period:]:
        result = alpha * value + (1 - alpha) * result
    return result


def rsi(values: list[float], period: int = 14) -> float | None:
    if period <= 0 or len(values) < period + 1:
        return None
    gains: list[float] = []
    losses: list[float] = []
    for previous, current in zip(values, values[1:]):
        delta = current - previous
        gains.append(max(delta, 0.0))
        losses.append(max(-delta, 0.0))
    avg_gain = sum(gains[:period]) / period
    avg_loss = sum(losses[:period]) / period
    for gain, loss in zip(gains[period:], losses[period:]):
        avg_gain = ((period - 1) * avg_gain + gain) / period
        avg_loss = ((period - 1) * avg_loss + loss) / period
    if avg_loss == 0:
        return 100.0
    return 100 - (100 / (1 + avg_gain / avg_loss))


def atr(highs: list[float], lows: list[float], closes: list[float], period: int = 14) -> float | None:
    """Average True Range for volatility-aware risk distances."""
    if period <= 0 or len(closes) < period + 1:
        return None
    if len(highs) != len(closes) or len(lows) != len(closes):
        return None
    trs: list[float] = []
    for i in range(1, len(closes)):
        trs.append(max(
            highs[i] - lows[i],
            abs(highs[i] - closes[i - 1]),
            abs(lows[i] - closes[i - 1]),
        ))
    if len(trs) < period:
        return None
    return sum(trs[-period:]) / period


def macd_histogram(values: list[float], fast: int = 12, slow: int = 26, signal: int = 9) -> float | None:
    """Last MACD histogram value; positive values indicate bullish momentum."""
    if fast <= 0 or slow <= fast or signal <= 0 or len(values) < slow + signal:
        return None
    ema_fast = _ema_series(values, fast)
    ema_slow = _ema_series(values, slow)
    if ema_fast is None or ema_slow is None:
        return None
    macd_line = [f - s for f, s in zip(ema_fast, ema_slow)]
    signal_line = _ema_series(macd_line, signal)
    if signal_line is None:
        return None
    return macd_line[-1] - signal_line[-1]


def _ema_series(values: list[float], period: int) -> list[float] | None:
    if period <= 0 or len(values) < period:
        return None
    alpha = 2 / (period + 1)
    result = [sum(values[:period]) / period]
    for value in values[period:]:
        result.append(alpha * value + (1 - alpha) * result[-1])
    pad = len(values) - len(result)
    return [result[0]] * pad + result


def volume_ratio(volumes: list[float], short: int = 10, long: int = 30) -> float:
    """Recent average volume divided by the preceding average volume."""
    if short <= 0 or long <= short or len(volumes) < long:
        return 1.0
    recent = sum(volumes[-short:]) / short
    older = sum(volumes[-long:-short]) / (long - short)
    if older <= 0:
        return 1.0
    return recent / older
