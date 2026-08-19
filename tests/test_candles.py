from analysis.candles import build_candles
from data.tabdeal import Trade


def test_build_candles_groups_trades():
    trades = [
        Trade(100, 2, 1_000),
        Trade(102, 1, 20_000),
        Trade(101, 3, 61_000),
    ]
    candles = build_candles(trades, 60)
    assert len(candles) == 2
    assert candles[0].open == 100
    assert candles[0].high == 102
    assert candles[0].low == 100
    assert candles[0].close == 102
    assert candles[0].volume == 3
