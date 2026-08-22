from execution import store
from execution.monitor import _unrealized_pnl, _hit_take_profit, _hit_stop_loss


def test_long_pnl_positive():
    assert _unrealized_pnl("LONG", 100.0, 110.0, 2.0) == 20.0


def test_short_pnl_positive():
    assert _unrealized_pnl("SHORT", 100.0, 90.0, 1.0) == 10.0


def test_tp_sl_long():
    assert _hit_take_profit("LONG", 110.0, 105.0) is True
    assert _hit_stop_loss("LONG", 94.0, 95.0) is True


def test_tp_sl_short():
    assert _hit_take_profit("SHORT", 90.0, 95.0) is True
    assert _hit_stop_loss("SHORT", 106.0, 105.0) is True
