from dataclasses import dataclass


@dataclass(frozen=True)
class MarketSnapshot:
    symbol: str
    last_price: float
    volume_score: float
    trend_score: float
    momentum_score: float
    orderbook_score: float
    data_fresh: bool = True


@dataclass(frozen=True)
class MarketScore:
    symbol: str
    score: float
    eligible: bool
    reasons: tuple[str, ...]


def score_market(snapshot: MarketSnapshot) -> MarketScore:
    if not snapshot.data_fresh:
        return MarketScore(snapshot.symbol, 0.0, False, ("stale market data",))
    values = [
        snapshot.volume_score,
        snapshot.trend_score,
        snapshot.momentum_score,
        snapshot.orderbook_score,
    ]
    if any(value < 0 or value > 100 for value in values):
        return MarketScore(snapshot.symbol, 0.0, False, ("invalid analysis score",))
    score = round(sum(values) / len(values), 2)
    eligible = score >= 70
    reasons = ("trend", "volume", "momentum", "order book") if eligible else ("score below threshold",)
    return MarketScore(snapshot.symbol, score, eligible, reasons)
