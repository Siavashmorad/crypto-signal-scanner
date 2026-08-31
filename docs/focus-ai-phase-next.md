# SignalYab Focus AI — next implementation phase

## Objective
Build a conservative market-focus/radar layer that continuously ranks supported spot markets, focuses analysis on the strongest setup, and switches focus when the setup deteriorates. It must not inflate scores or bypass existing execution gates.

## Requirements
- Multi-timeframe analysis: 1D, 4H, 1H, 15m where data is available.
- Evaluate trend/structure, momentum, volatility, volume, support/resistance, entry quality, stop-loss distance, take-profit quality and risk/reward.
- Produce an auditable score with component breakdown; no artificial score inflation.
- Focus on one best candidate while retaining a ranked shortlist for failover.
- Re-evaluate on every market-data refresh; switch focus only when the replacement has materially better quality or the current setup becomes invalid/stale.
- States: FOCUS, WATCH, WAIT, INVALID, STALE.
- Generate Android notifications from background monitoring only. Background must remain read-only.
- Notification thresholds must be configurable, with high-confidence alerting at 93/95, but thresholds do not bypass LiveTradingGate.
- For SPOT, bearish signals are informational only: no short action.
- Automatic Spot execution remains behind all existing safety gates and must not be called from background workers.
- Preserve existing Tabdeal host `https://api1.tabdeal.org`, max notional 50 USDT, min sample 20, minimum expectancy R 0.05, and existing score/gate logic.
- Keep MT5 read-only/analysis-only unless separately enabled later.
- Add tests for ranking, focus switching, stale invalidation, score breakdown, no inflation, notification threshold, and background no-order behavior.

## Deliverables
1. Focus/radar domain model and service.
2. Market-data aggregation using existing adapters; do not rewrite Scanner Engine.
3. Focus UI with current candidate, reason codes, score breakdown, freshness and invalidation reason.
4. Background monitoring integration using existing Android background mechanism, notifications only.
5. Regression tests and CI.
6. Release APK only after all CI checks pass.

## Safety rule
Unknown/stale/failed market state => NO TRADE. Background => NO ORDER. Never claim a 9:1 win rate or guaranteed profit; validate performance through paper-trading statistics first.
