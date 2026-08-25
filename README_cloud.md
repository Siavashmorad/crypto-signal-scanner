# Cloud Market Intelligence (24/7 path)

## What this is

Backend-side Market Worker that runs **on the server process**, independent of the Flutter APK lifecycle.

- Reuses existing `scanner.engine.scan_symbol` and `best_market.extract_symbols`
- Uses real Tabdeal public data only (`https://api1.tabdeal.org`)
- Never invents indicators or candles
- Never places orders
- TradingView alerts remain **hints** only (via existing AlertStore)
- Optional FCM push when credentials + device tokens are present

## Enable

On Render (or any **always-on** host), set:

```
CLOUD_WORKER_ENABLED=true
CLOUD_WORKER_INTERVAL_SEC=90
CLOUD_WORKER_MAX_SYMBOLS=16
CLOUD_WORKER_MIN_SCORE=70
CLOUD_WORKER_TIMEFRAME=15m
CLOUD_WORKER_OPPORTUNITY_TTL_SECONDS=900
CLOUD_WORKER_NOTIFICATION_COOLDOWN_SECONDS=900
```

Default is **false** (safe). Flutter continuous poll remains available either way.

## FCM (closed-app notifications)

1. Create a Firebase project and enable Cloud Messaging.
2. Put the **legacy server key** in host env only (never commit):

```
FCM_SERVER_KEY=...your key...
```

3. Flutter must obtain an FCM device token and `POST /devices/register` (owner auth) with:

```json
{
  "device_id": "unique-device-id",
  "fcm_token": "...",
  "platform": "android",
  "enabled": true
}
```

4. When the worker finds a high-score opportunity and cooldown allows, it dispatches FCM.
5. Without `FCM_SERVER_KEY` or registered tokens, scan still works; push is skipped gracefully.

**No Firebase private key or server key is stored in Git.**

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/opportunities/health` | public | worker + FCM + device status |
| GET | `/opportunities/latest` | owner Basic | ranked fresh opportunities |
| POST | `/opportunities/scan-now` | owner Basic | one-shot scan |
| POST | `/devices/register` | owner Basic | register/rotate FCM token |
| POST | `/devices/disable` | owner Basic | disable push for device |
| POST | `/devices/remove` | owner Basic | remove device |
| GET | `/devices/list` | owner Basic | list devices (token tails only) |

## Honest 24/7 status

- **Code ready** for cloud-side continuous scan while the web process is alive.
- **Render free tier** may sleep after idle → **not** guaranteed always-on.
- **True 24/7** requires a paid always-on instance (or external cron hitting `/opportunities/scan-now`).
- **Android Push (FCM)** requires `FCM_SERVER_KEY` + at least one registered device token.
- Without host credentials, deploy cannot be performed from every environment:

  `RENDER DEPLOY NOT POSSIBLE — CREDENTIAL REQUIRED`

## Flutter role after this change

APK still:

- Settings / Safe Mode / Confirmation
- Wallet / FuturesExecutionService
- Can poll `/opportunities/latest` in addition to TV alerts
- Must **revalidate** before any order
- Local notifications remain for process-alive cases

When APK is closed or process killed, the **server** can still scan (if worker enabled and process up).  
Delivery of notification to a closed app requires FCM (credentials + token registration).

## Absolute safety

- Cloud worker **never** calls Tabdeal private order APIs.
- Cloud worker **never** places LONG/SHORT orders.
- Safe Mode and user confirmation remain mandatory on device.
- `MAX_POSITION_NOTIONAL_USDT=50` unchanged.
- Stale opportunities are not actionable for execution.
