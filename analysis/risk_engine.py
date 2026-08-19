from dataclasses import dataclass


@dataclass(frozen=True)
class RiskSetup:
    entry: float
    stop_loss: float
    take_profit: float
    capital: float
    risk_percent: float = 1.0

    @property
    def risk_budget(self) -> float:
        return self.capital * self.risk_percent / 100.0

    @property
    def risk_per_unit(self) -> float:
        return abs(self.entry - self.stop_loss)

    @property
    def position_size(self) -> float:
        if self.risk_per_unit <= 0:
            return 0.0
        return self.risk_budget / self.risk_per_unit

    @property
    def reward_risk(self) -> float:
        risk = self.risk_per_unit
        if risk <= 0:
            return 0.0
        return abs(self.take_profit - self.entry) / risk


def valid_setup(setup: RiskSetup, minimum_reward_risk: float = 2.0) -> bool:
    return setup.entry > 0 and setup.stop_loss > 0 and setup.take_profit > 0 and setup.position_size > 0 and setup.reward_risk >= minimum_reward_risk
