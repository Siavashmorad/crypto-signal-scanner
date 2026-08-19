# Crypto Signal Scanner

A **signal-only** cryptocurrency market scanner for Tabdeal, with a Persian-first Android UI.

## Current capabilities

- Tabdeal public `exchangeInfo`, `trades` and `depth` integration in the Python core.
- Builds `1m`, `5m`, `15m` and `1h` candles from trades.
- EMA/RSI and order-book imbalance analysis in the core scanner.
- Risk-based position sizing from capital and maximum risk.
- `LONG`, `SHORT` or `NO_TRADE` decisions.
- Single-owner protected backend authentication.
- Android Flutter app with Persian UI, English switch, dark/light mode and private login gate.
- Mobile scanner currently reads public Tabdeal market data directly and never places orders.
- GitHub Actions release APK build.

## Safety

The application is signal-only. It does not submit orders or store exchange trading credentials.

## Roadmap

1. Full-market ranking of every eligible USDT market.
2. ATR/volatility-aware stops and multiple take-profit levels.
3. Backtesting and paper trading.
4. Alerts and richer charts.
5. Stronger device-bound owner authentication.
6. Optional execution only after extensive validation and an explicit separate safety layer.
