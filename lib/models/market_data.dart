class TradePoint {
  final double price;
  final double quantity;
  final int timestampMs;

  const TradePoint({required this.price, required this.quantity, required this.timestampMs});
}

class Candle {
  final int timestampMs;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({required this.timestampMs, required this.open, required this.high, required this.low, required this.close, required this.volume});
}

class MarketSignal {
  final String symbol;
  final String side;
  final double entry;
  final double stopLoss;
  final double tp1;
  final double tp2;
  final double tp3;
  final double atr;
  final double confidence;
  final double riskReward;
  final DateTime timestamp;

  const MarketSignal({required this.symbol, required this.side, required this.entry, required this.stopLoss, required this.tp1, required this.tp2, required this.tp3, required this.atr, required this.confidence, required this.riskReward, required this.timestamp});
}
