from analysis.risk_engine import RiskSetup, valid_setup


def test_position_size_respects_risk_budget():
    setup = RiskSetup(
        entry=100.0,
        stop_loss=98.0,
        take_profit=106.0,
        capital=10_000_000,
        risk_percent=1.0,
    )
    assert setup.risk_budget == 100_000
    assert setup.position_size == 50_000
    assert setup.reward_risk == 3.0
    assert valid_setup(setup)


def test_invalid_zero_distance_is_rejected():
    setup = RiskSetup(100, 100, 110, 10_000_000)
    assert setup.position_size == 0
    assert not valid_setup(setup)
