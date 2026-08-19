from analysis.indicators import ema, rsi


def test_ema_returns_none_without_enough_data():
    assert ema([1, 2], 3) is None


def test_ema_basic():
    value = ema([1, 2, 3, 4, 5], 3)
    assert value is not None
    assert value > 3


def test_rsi_uptrend():
    value = rsi(list(range(1, 20)), 14)
    assert value == 100.0
