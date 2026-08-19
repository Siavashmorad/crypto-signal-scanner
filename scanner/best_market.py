from __future__ import annotations

from dataclasses import dataclass

from scanner.engine import scan_symbol
from data.tabdeal import TabdealPublicClient


@dataclass(frozen=True)
class RankedSignal:
    signal: dict


def extract_symbols(exchange_info: object, quote_asset: str = "USDT") -> list[str]:
    """Extract tradable symbols from common exchangeInfo response shapes."""
    if not isinstance(exchange_info, dict):
        return []
    rows = exchange_info.get("symbols", [])
    result: list[str] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        symbol = str(row.get("symbol", ""))
        quote = str(row.get("quoteAsset", row.get("quoteCurrency", ""))).upper()
        status = str(row.get("status", "TRADING")).upper()
        if symbol and (not quote or quote == quote_asset.upper()) and status in {"TRADING", "ENABLED", ""}:
            result.append(symbol)
    return sorted(set(result))


def best_market(client: TabdealPublicClient, timeframe: str, capital: float, risk_percent: float, max_markets: int = 50) -> dict:
    symbols = extract_symbols(client.exchange_info())
    if not symbols:
        return {"direction": "NO_TRADE", "reason": "No eligible markets returned by exchangeInfo"}
    ranked: list[dict] = []
    for symbol in symbols[:max_markets]:
        try:
            signal = scan_symbol(client, symbol, timeframe, capital, risk_percent)
            if signal.direction != "NO_TRADE":
                ranked.append({"symbol": symbol, "score": signal.score, "signal": signal})
        except Exception:
            continue
    if not ranked:
        return {"direction": "NO_TRADE", "reason": "No market met the signal and risk filters", "markets_checked": min(len(symbols), max_markets)}
    ranked.sort(key=lambda row: row["score"], reverse=True)
    signal = ranked[0]["signal"]
    return {
        "symbol": signal.symbol,
        "direction": signal.direction,
        "timeframe": signal.timeframe,
        "entry": signal.entry,
        "stop_loss": signal.stop_loss,
        "take_profit": signal.take_profit,
        "score": signal.score,
        "reasons": signal.reasons,
        "markets_checked": min(len(symbols), max_markets),
    }
