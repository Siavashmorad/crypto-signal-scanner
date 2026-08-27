# Cloud Market Intelligence + FCM Push

## Architecture

```
Cloud Worker (server) → rank → FCM_SERVER_KEY → Android OS notification
                                      ↓
                         User taps → SignalYab opens
                                      ↓
                         Revalidate → Gate → Risk → Confirm
                                      ↓
                         FuturesExecutionService → Tabdeal
```

Cloud **never** places orders. Notification **never** auto-trades.

## Flutter FCM client

- `lib/services/firebase_push_service.dart` — token, register, foreground/background
- `lib/services/fcm_opportunity_payload.dart` — parse data payload (unit-tested)
- Dependencies: `firebase_core`, `firebase_messaging`

### Live Android FCM requires

1. Firebase project with Android app package: `com.signalyab.crypto_signal_scanner`
2. `google-services.json` (local or CI secret `GOOGLE_SERVICES_JSON`) — **never commit real file**
3. Backend ENV: `FCM_SERVER_KEY=<legacy server key>` (current dispatcher uses **legacy** HTTP API)
4. Always-on host with `CLOUD_WORKER_ENABLED=true` (Render **free** sleeps → not 24/7)
5. App login + backend URL so token posts to `/devices/register`

Without these: **FCM LIVE = CREDENTIAL REQUIRED**

Placeholder `google-services.json` is injected in CI so APK still builds; runtime Firebase init fails soft.

### FCM auth note (HTTP v1)

Current server dispatcher: **legacy** `https://fcm.googleapis.com/fcm/send` + `FCM_SERVER_KEY`.

Firebase is deprecating legacy server keys. Production path preferred later:

- Service account JSON in server ENV only (`FIREBASE_CREDENTIALS_JSON` or secret file)
- OAuth2 access token → FCM HTTP v1 `projects/{id}/messages:send`
- Never put service-account JSON in Git or the APK

Migration is **not** required for code readiness; it is required before relying on long-term Google support of the legacy key.

## Device endpoints (owner Basic auth)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/devices/register` | register/rotate token |
| POST | `/devices/disable` | disable pushes |
| POST | `/devices/remove` | remove device |
| GET | `/devices/list` | list (token tails only) |

Payload register: `device_id`, `fcm_token`, `platform`, `enabled`, `app_version`

## Honest 24/7

| Layer | Status |
|-------|--------|
| Code: cloud scan independent of APK | READY |
| Code: FCM client + dispatcher | READY |
| Runtime: always-on server | HOST REQUIRED |
| Runtime: FCM credentials | CREDENTIAL REQUIRED |
| E2E closed-app push | NOT VERIFIED until credentials + host |

Free Render sleep ≠ 24/7.

## Safety

- MAX_POSITION_NOTIONAL_USDT=50
- api1.tabdeal.org only
- No FCM server key in APK/Git
- Scanner / Quant / FuturesExecution unchanged
