# Crypto Signal Scanner

A **signal-only** cryptocurrency market scanner for Tabdeal. It reads public market data, analyzes markets and returns a trade setup. It never places orders.

## Current capabilities

- Tabdeal public `exchangeInfo`, `trades` and `depth` integration.
- Builds `1m`, `5m`, `15m` and `1h` candles from trades.
- EMA and RSI analysis.
- Order-book imbalance scoring.
- Risk-based position sizing from capital and maximum risk.
- `LONG`, `SHORT` or `NO_TRADE` decisions.
- Protected API with exactly one configured owner account.
- No registration and no trading credentials in the application.
- Docker and GitHub Actions test workflow.

Tabdeal's official documentation identifies public market endpoints as `NONE` security, while trading endpoints require API credentials/signatures. This project intentionally uses only the public market side for now. fileciteturn6file0

## Authentication

Set these only as deployment secrets/environment variables:

- `SIGNAL_SCANNER_USERNAME`
- `SIGNAL_SCANNER_PASSWORD_HASH`

Generate a hash with `auth.single_user.password_hash()` in a trusted environment. Do **not** commit the password or hash to source control.

## Run

```bash
pip install -r requirements.txt
uvicorn main:app --reload
```

Protected endpoint:

`POST /scan`

Example body:

```json
{
  "symbol": "BTCUSDT",
  "timeframe": "15m",
  "capital": 10000000,
  "risk_percent": 1
}
```

The service remains signal-only. Real-money execution, API keys and automated order placement are deliberately out of scope for this stage.

## Roadmap

1. Multi-market scanner that ranks every eligible USDT market.
2. Better candle aggregation and data freshness checks.
3. ATR/volatility-aware stops and multiple take-profit levels.
4. Backtesting and paper trading.
5. Alerts and mobile/web UI.
6. Optional execution only after extensive validation and an explicit separate safety layer.
