import 'package:flutter/material.dart';

import '../services/account_balance.dart';
import '../services/local_trade_store.dart';
import '../services/tabdeal_trade.dart';

class WalletPage extends StatefulWidget {
  final bool english;
  const WalletPage({super.key, required this.english});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  AccountSnapshot? spot;
  FuturesBalanceSnapshot? futures;
  FuturesPositionsSnapshot? positions;
  BalanceHealth health = BalanceHealth.offline;
  DateTime? lastUpdate;
  bool loading = false;
  String? error;
  final store = LocalTradeStore();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final key = await store.apiKey();
      final secret = await store.apiSecret();
      if (key.isEmpty || secret.isEmpty) {
        setState(() {
          error = widget.english ? 'API not configured' : 'کلید API تنظیم نشده';
          health = BalanceHealth.offline;
          loading = false;
          spot = null;
          futures = null;
          positions = null;
        });
        return;
      }
      final client = TabdealTradeClient(apiKey: key, apiSecret: secret);
      final s = await client.accountSnapshot();
      final f = await client.futuresBalanceSnapshot();
      final p = await client.futuresPositionsSnapshot();
      client.dispose();
      if (!mounted) return;
      setState(() {
        spot = s;
        futures = f;
        positions = p;
        lastUpdate = DateTime.now();
        loading = false;
        error = null;
        health = (s.available || (f.available && f.futuresActive))
            ? BalanceHealth.live
            : BalanceHealth.offline;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
        health = BalanceHealth.offline;
      });
    }
  }

  String _fmt(double v) {
    if (v.abs() >= 1) return v.toStringAsFixed(4);
    return v.toStringAsFixed(8);
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'Wallet' : 'کیف پول'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${en ? "Health" : "سلامت"}: ${balanceHealthLabel(health)}'
                '${lastUpdate != null ? "  ·  $lastUpdate" : ""}',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: const TextStyle(color: Colors.red)),
                ),
              if (loading) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(en ? 'Spot' : 'اسپات',
                  style: Theme.of(context).textTheme.titleMedium),
              if (spot == null || !spot!.available)
                Text(spot?.error ?? (en ? 'No data' : 'بدون داده'))
              else
                ...spot!.balances.map(
                  (b) => ListTile(
                    title: Text(b.asset),
                    subtitle: Text(
                      '${en ? "Free" : "آزاد"}: ${_fmt(b.free)}  '
                      '${en ? "Locked" : "قفل"}: ${_fmt(b.locked)}',
                    ),
                    trailing: Text(_fmt(b.total)),
                  ),
                ),
              const Divider(),
              Text(en ? 'Futures' : 'فیوچرز',
                  style: Theme.of(context).textTheme.titleMedium),
              if (futures == null)
                Text(en ? 'No data' : 'بدون داده')
              else if (!futures!.futuresActive)
                Text(
                  en
                      ? 'Futures not active for this account'
                      : 'حساب Futures برای این کاربر فعال نیست',
                  style: const TextStyle(color: Colors.orange),
                )
              else if (!futures!.available)
                Text(futures!.error ?? '',
                    style: const TextStyle(color: Colors.red))
              else
                ...futures!.balances.map(
                  (b) => ListTile(
                    title: Text(b.asset),
                    subtitle: Text(
                      '${en ? "Wallet" : "کیف"}: ${_fmt(b.walletBalance)}\n'
                      '${en ? "Available" : "قابل استفاده"}: ${_fmt(b.availableBalance)}\n'
                      'Cross: ${_fmt(b.crossWalletBalance)}  uPnL: ${_fmt(b.crossUnPnl)}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              const Divider(),
              Text(en ? 'Open Positions' : 'پوزیشن‌های باز',
                  style: Theme.of(context).textTheme.titleMedium),
              if (positions == null ||
                  !positions!.futuresActive ||
                  positions!.positions.isEmpty)
                Text(en ? 'No open positions' : 'پوزیشن بازی نیست')
              else
                ...positions!.positions.map(
                  (p) => Card(
                    child: ListTile(
                      title: Text(
                        '${p.symbol} ${p.isLong ? "LONG" : "SHORT"}',
                        style: TextStyle(
                          color: p.isLong ? Colors.green : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'Qty ${_fmt(p.positionAmt.abs())}  Entry ${_fmt(p.entryPrice)}\n'
                        'Mark ${_fmt(p.markPrice)}  uPnL ${_fmt(p.unRealizedProfit)}\n'
                        'Lev ${p.leverage.toStringAsFixed(0)}x  Liq ${_fmt(p.liquidationPrice)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
