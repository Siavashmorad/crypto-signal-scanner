# Crypto Signal Scanner

A **signal-only** cryptocurrency market scanner for Tabdeal. It reads public market data, analyzes markets and returns a trade setup. It never places orders.

## Current capabilities

- Tabdeal public `exchangeInfo`, `trades` and `depth` integration.
- Builds `1m`, `5m`, `15m` and `1h` candles from trades.
- EMA, RSI and ATR analysis.
- Order-book imbalance scoring.
- Risk-based position sizing from capital and maximum risk.
- `LONG`, `SHORT` or `NO_TRADE` decisions.
- Multiple take-profit levels.
- Full USDT market discovery and bounded concurrent scanning in the Flutter client.
- Protected API with exactly one configured owner account.
- No registration and no trading credentials in the application.
- Private server-side AI market analyst integration.
- Docker and GitHub Actions test/build workflow.

Tabdeal's official documentation identifies public market endpoints as `NONE` security, while trading endpoints require API credentials/signatures. This project intentionally uses only the public market side for now.

## AI Market Analyst

The AI analyst receives an already-computed signal and returns a structured second opinion containing:

- trend and momentum assessment
- signal quality
- risk level
- bullish and bearish scenarios
- invalidation condition
- `WATCH`, `LONG_BIAS`, `SHORT_BIAS` or `AVOID` recommendation
- analytical confidence
- reasons behind the assessment

The AI is **not** an execution engine. The application never submits exchange orders. The user manually decides whether to open a position.

The OpenAI credential is server-side only. Never put `OPENAI_API_KEY` in Flutter source code or the APK.

Required backend environment variables:

- `OPENAI_API_KEY`
- `OPENAI_MODEL` (default example: `gpt-4.1-mini`)
- `OPENAI_RESPONSES_URL` (default: `https://api.openai.com/v1/responses`)

The Flutter release accepts the private backend URL through the build-time variable `AI_BACKEND_URL`.

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

Protected endpoints:

`POST /scan`

`POST /best`

`POST /ai/analyze`

Example scan body:

```json
{
  "symbol": "BTCUSDT",
  "timeframe": "15m",
  "capital": 10000000,
  "risk_percent": 1
}
```

The service remains signal-only. Real-money execution, API keys for exchange trading, and automated order placement are deliberately out of scope for this stage.

## Private backend deployment

A `render.yaml` blueprint is included for a private API deployment. After deployment, configure the backend secrets, including `OPENAI_API_KEY`, and use the resulting HTTPS API URL as the Flutter `AI_BACKEND_URL` build variable.

Do not commit any real secret.

## Roadmap

1. Persistent signal history.
2. Professional interactive charts.
3. Historical-data backtesting.
4. AI analysis across the ranked top opportunities.
5. Alerts and richer mobile UI.
6. Optional execution only after extensive validation and an explicit separate safety layer.
