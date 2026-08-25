# Cloud Market Intelligence (24/7 path)

## What this is

Backend-side Market Worker that runs **on the server process**, independent of the Flutter APK lifecycle.

- Reuses existing `scanner.engine.scan_symbol` and `best_market.extract_symbols`
- Uses real Tabdeal public data only (`https://api1.tabdeal.org`)
- Never invents indicators or candles
- Never places orders
- TradingView alerts remain **hints** only (via existing AlertStore)

## Enable

On Render (or any host), set:

```
CLOUD_WORKER_ENABLED=true
CLOUD_WORKER_INTERVAL_SEC=90
CLOUD_WORKER_MAX_SYMBOLS=16
CLOUD_WORKER_MIN_SCORE=70
```

Default is **false** (safe). Flutter continuous poll remains available either way.

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/opportunities/health` | public | worker status |
| GET | `/opportunities/latest` | owner Basic | ranked fresh opportunities |
| POST | `/opportunities/scan-now` | owner Basic | one-shot scan |

## Honest 24/7 status

- **Code ready** for cloud-side continuous scan while the web process is alive.
- **Render free tier** may sleep after idle → not guaranteed always-on.
- **True 24/7** requires a paid always-on instance (or external cron hitting `/opportunities/scan-now`).
- **Android Push (FCM)** is **not configured** until `FCM_SERVER_KEY` / Firebase credentials are provided.
- Without Render credentials, deploy cannot be performed from this environment:

  `RENDER DEPLOY NOT POSSIBLE — CREDENTIAL REQUIRED`

## Flutter role after this change

APK still:

- Settings / Safe Mode / Confirmation
- Wallet / FuturesExecutionService
- Can poll `/opportunities/latest` in addition to TV alerts
- Must **revalidate** before any order

When APK is closed, the **server** can still scan (if worker enabled and process up).  
Delivery of notification to a closed app requires FCM (not yet wired).
