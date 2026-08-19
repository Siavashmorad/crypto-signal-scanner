# Crypto Signal Scanner

Signal-only cryptocurrency market scanner for Tabdeal market data.

## Scope

This project scans available markets and produces a trade setup without placing orders.

A signal may contain:

- Symbol
- LONG / SHORT / NO TRADE
- Timeframe
- Entry zone
- Stop loss
- Take-profit levels
- Risk/reward
- Suggested position size from user capital and risk budget
- Signal score and analysis reasons

## Safety

The first version does **not** submit orders, use trading credentials, or manage positions automatically. Signals must be validated with backtesting and paper trading before real-money use.

## Initial architecture

- `app/` — application and API integration
- `analysis/` — market data, candles, indicators, scoring and risk engine
- `tests/` — unit and integration tests
- `.github/workflows/` — CI

## Planned data flow

`Tabdeal REST trades/depth -> candle builder -> indicators -> market scorer -> risk engine -> signal`

The scanner should prefer `NO TRADE` when market data is stale, incomplete, contradictory, or risk constraints cannot be satisfied.
