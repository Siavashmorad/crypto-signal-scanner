# SignalYab Focus AI — implementation status

The Focus AI layer continuously ranks a bounded supported-market universe, deep-checks the strongest candidates using real market data, focuses on one candidate, and switches only when the replacement is materially better or the current setup becomes invalid/stale.

Safety contract:
- No artificial score inflation.
- SPOT bearish signals remain informational; no spot short.
- Background monitoring is read-only and never calls an order path.
- Unknown/stale/failed market state => NO TRADE.
- Preserve `https://api1.tabdeal.org`, max notional 50 USDT, min sample 20, minimum expectancy R 0.05, and existing LiveTradingGate.
- MT5 remains read-only/analysis-only.
- A 9:1 win rate or guaranteed profit must never be claimed; performance must be established from measured paper/live outcomes.

Implementation status:
- Persistent focus selection across foreground/background runs.
- Bounded market scan plus deep candidate re-check.
- Material focus-switching policy.
- FOCUS / WAIT / INVALID / STALE / NO SETUP states.
- Configurable background notification thresholds 80/90/93/95.
- One-off background test trigger and last-run status UI.
- Regression tests for focus selection and anti-stale/non-buy selection.
