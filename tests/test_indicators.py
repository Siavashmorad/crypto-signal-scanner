from analysis.indicators import atr, ema, macd_histogram, rsi, volume_ratio


def test_ema_returns_none_without_enough_data():
    assert ema([1, 2], 3) is None


def test_ema_basic():
    value = ema([1, 2, 3, 4, 5], 3)
    assert value is not None
    assert value > 3


def test_rsi_uptrend():
    value = rsi(list(range(1, 20)), 14)
    assert value == 100.0


def test_atr_returns_positive_volatility():
    closes = [10, 11, 12, 11, 13, 14, 15, 14, 16, 17, 18, 17, 19, 20, 21, 20]
    highs = [v + 0.5 for v in closes]
    lows = [v - 0.5 for v in closes]
    value = atr(highs, lows, closes, 14)
    assert value is not None
    assert value > 0


def test_macd_histogram_is_available_with_enough_history():
    values = [100 + i * 0.5 + (i % 4) * 0.1 for i in range(50)]
    value = macd_histogram(values)
    assert value is not None


def test_volume_ratio_detects_rising_volume():
    volumes = [10.0] * 20 + [20.0] * 10
    assert volume_ratio(volumes) > 1.0
