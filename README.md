# SignalYab (سیگنال‌یاب)

Production-oriented **Tabdeal** scanner with **approval-gated** real trading.

## Real stack

| Layer | Source |
|-------|--------|
| Market data | Tabdeal public API (live order book + trades) |
| Best market | Ranked multi-symbol scan (EMA/RSI/ATR/order-book) |
| AI second opinion | OpenAI on private backend (`OPENAI_API_KEY`) |
| Orders | Tabdeal TRADE API (`TABDEAL_API_KEY` / `SECRET`) |
| PnL | Live mid price from order book |
| Control | **Your explicit Approve** before every open/close |

No software guarantees profit. Real money can be lost.

## End-to-end business flow

1. Online scan of USDT markets on Tabdeal
2. Rank best setups
3. Optional AI analysis
4. You review → Propose OPEN → **Approve** → live/paper order
5. `/execution/monitor` tracks mark price + unrealized PnL
6. On TP or SL hit → system **proposes CLOSE** (still needs your Approve)
7. You Approve → position closes on exchange

## Execution modes

| `EXECUTION_MODE` | Behavior |
|------------------|----------|
| `signal_only` | Signals only |
| `paper` | Virtual fills after Approve (practice) |
| `live_with_approval` | **Real money** Tabdeal MARKET orders after Approve |

### Live (real money) checklist

```bash
EXECUTION_MODE=live_with_approval
TABDEAL_API_KEY=...
TABDEAL_API_SECRET=...
OPENAI_API_KEY=...
MAX_OPEN_POSITIONS=3
MAX_POSITION_NOTIONAL_USDT=50
MAX_RISK_PERCENT_PER_TRADE=1
MAX_DAILY_LOSS_USDT=30
```

Start with the smallest notional you can afford to lose.

## API (owner auth)

- `POST /scan` `POST /best` `POST /ai/analyze`
- `GET /execution/status` `GET /execution/pending`
- `GET /execution/positions` `GET /execution/monitor`
- `POST /execution/propose-open` `POST /execution/propose-close`
- `POST /execution/approve` `POST /execution/reject`

## Security

- Trading keys only on the server — never in the APK
- Single-owner HTTP Basic auth
- Approve required for every order path
