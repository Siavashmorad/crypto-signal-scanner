import 'dart:async';

import 'package:flutter/material.dart';
import '../services/execution_service.dart';

/// Live positions, mark price, unrealized PnL, auto-monitor toggle.
class PnlDashboard extends StatefulWidget {
  final bool english;
  final String? username;
  final String? password;
  final ExecutionService execution;
  final VoidCallback? onPendingChanged;

  const PnlDashboard({
    super.key,
    required this.english,
    required this.username,
    required this.password,
    required this.execution,
    this.onPendingChanged,
  });

  @override
  State<PnlDashboard> createState() => _PnlDashboardState();
}

class _PnlDashboardState extends State<PnlDashboard> {
  bool autoMonitor = false;
  bool loading = false;
  String? error;
  List<Map<String, dynamic>> positions = [];
  double totalPnl = 0;
  List<Map<String, dynamic>> autoProposals = [];
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> runMonitor() async {
    if (widget.username == null ||
        widget.password == null ||
        !widget.execution.configured) {
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await widget.execution.monitor(
        username: widget.username!,
        password: widget.password!,
      );
      if (!mounted) return;
      final list = (data['positions'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final proposals = (data['auto_close_proposals'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      setState(() {
        positions = list;
        totalPnl = (data['total_unrealized_pnl'] as num?)?.toDouble() ?? 0;
        autoProposals = proposals;
        loading = false;
      });
      if (proposals.isNotEmpty) {
        widget.onPendingChanged?.call();
        if (mounted) {
          final en = widget.english;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(en
                  ? 'TP/SL hit — close proposal waiting for your Approve'
                  : 'TP/SL خورد — درخواست بستن منتظر تأیید شماست'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _toggleAuto(bool value) {
    setState(() => autoMonitor = value);
    _timer?.cancel();
    if (value) {
      runMonitor();
      _timer = Timer.periodic(const Duration(seconds: 20), (_) => runMonitor());
    }
  }

  String _fmt(dynamic v, {int digits = 4}) {
    final n = double.tryParse('$v');
    if (n == null) return '-';
    if (n.abs() >= 1000) return n.toStringAsFixed(2);
    if (n.abs() >= 1) return n.toStringAsFixed(digits);
    return n.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    if (!widget.execution.configured) {
      return const SizedBox.shrink();
    }

    final pnlColor = totalPnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    en ? 'Live PnL dashboard' : 'داشبورد سود و زیان زنده',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: en ? 'Refresh now' : 'بروزرسانی',
                  onPressed: loading ? null : runMonitor,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(en ? 'Auto monitor (20s)' : 'مانیتور خودکار (۲۰ ثانیه)'),
              subtitle: Text(en
                  ? 'Checks mark price & proposes CLOSE on TP/SL'
                  : 'قیمت لحظه‌ای را چک می‌کند و در TP/SL درخواست بستن می‌سازد'),
              value: autoMonitor,
              onChanged: _toggleAuto,
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(en ? 'Total unrealized PnL' : 'مجموع سود/زیان باز'),
                Text(
                  _fmt(totalPnl, digits: 4),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: pnlColor,
                  ),
                ),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (positions.isEmpty && !loading)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(en
                    ? 'No open positions.'
                    : 'پوزیشن بازی وجود ندارد.'),
              ),
            ...positions.map((p) {
              final symbol = '${p['symbol'] ?? ''}';
              final side = '${p['side'] ?? ''}';
              final entry = p['entry'];
              final mark = p['mark_price'];
              final pnl = (p['unrealized_pnl'] as num?)?.toDouble() ?? 0;
              final pct = (p['unrealized_pnl_percent'] as num?)?.toDouble() ?? 0;
              final tpHit = p['take_profit_hit'] == true;
              final slHit = p['stop_loss_hit'] == true;
              final color = pnl >= 0 ? Colors.green.shade700 : Colors.red.shade700;
              return Card(
                margin: const EdgeInsets.only(top: 10),
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$symbol • $side',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            '${_fmt(pnl)} (${pct.toStringAsFixed(2)}%)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                          '${en ? 'Entry' : 'ورود'}: ${_fmt(entry)}  →  ${en ? 'Mark' : 'فعلی'}: ${_fmt(mark)}'),
                      Text(
                          '${en ? 'Qty' : 'حجم'}: ${_fmt(p['quantity'])}  |  mode: ${p['mode'] ?? '-'}'),
                      if (tpHit || slHit)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Chip(
                            label: Text(tpHit
                                ? (en ? 'TP hit — approve CLOSE' : 'TP خورد — بستن را تأیید کنید')
                                : (en ? 'SL hit — approve CLOSE' : 'SL خورد — بستن را تأیید کنید')),
                            backgroundColor: tpHit
                                ? Colors.green.shade100
                                : Colors.red.shade100,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            if (autoProposals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  en
                      ? '${autoProposals.length} auto CLOSE proposal(s) added — use Approve panel'
                      : '${autoProposals.length} درخواست بستن خودکار اضافه شد — از پنل تأیید استفاده کنید',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
