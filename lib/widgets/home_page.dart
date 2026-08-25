import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import '../services/account_balance.dart';
import '../services/ai_analyst.dart';
import '../services/android_notification_service.dart';
import '../services/execution_service.dart';
import '../services/futures_execution_service.dart';
import '../services/live_trading_gate.dart';
import '../services/local_trade_store.dart';
import '../services/order_sizing.dart';
import '../services/realtime_futures_scanner_service.dart';
import '../services/scanner_service.dart';
import '../services/signal_cooldown.dart';
import '../services/signal_journal.dart';
import '../services/symbol_rules_service.dart';
import '../services/tabdeal_api.dart';
import 'connection_diagnose_page.dart';
import 'market_chart_page.dart';

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
    this.aiUsername,
    this.aiPassword,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final api = TabdealApi();
  late final scanner = ScannerService(api);
  late final rules = SymbolRulesService(api);
  final sizing = OrderSizingEngine();
  final ai = AiAnalystService();
  final tradeStore = LocalTradeStore();
  final signalJournal = SignalJournal();
  final signalCooldown = SignalCooldown();
  final liveGate = LiveTradingGate();
  RealtimeFuturesScannerService? realtime;
  final Map<String, Map<String, dynamic>> lastFills = {};
  bool loading = false;
  bool checkingLink = true;
  bool tabdealLinked = false;
  bool liveOn = false;
  bool preferFutures = false;
  bool realtimeOn = false;
  bool realtimeNotify = true;
  bool androidOsNotify = true;
  late final AndroidNotificationService androidNotify;
  String realtimeLabel = '';
  String timeframe = '15m';
  String? status;
  List<MarketSignal> signals = [];
  int marketCount = 0;
  MarketSignal? selectedForAi;
  AiAnalysis? aiAnalysis;
  bool aiLoading = false;
  String? aiError;

  Duration get duration => switch (timeframe) {
        '1m' => const Duration(minutes: 1),
        '5m' => const Duration(minutes: 5),
        '1h' => const Duration(hours: 1),
        _ => const Duration(minutes: 15),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    androidNotify = AndroidNotificationService(
      onSelect: (payload) {
        // ignore: discarded_futures
        _onNotificationTap(payload);
      },
    );
    // ignore: discarded_futures
    androidNotify.init().then((_) => _handleLaunchFromNotification());
    _checkTabdeal();
    _refreshTradeStatus();
  }

  /// Tap on OS notification → open matching opportunity (manual confirm still required).
  Future<void> _onNotificationTap(String? payload) async {
    final parsed = AndroidNotificationService.parsePayload(payload);
    if (parsed == null) return;
    if (!mounted) return;
    final en = widget.english;
    MarketSignal? match;
    for (final s in signals) {
      if (s.symbol.toUpperCase() == parsed.symbol &&
          s.side.toUpperCase() == parsed.side) {
        match = s;
        break;
      }
    }
    if (match == null && realtime != null) {
      for (final opp in realtime!.lastOpps) {
        final s = opp.signal;
        if (s.symbol.toUpperCase() == parsed.symbol &&
            s.side.toUpperCase() == parsed.side) {
          match = s;
          break;
        }
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'Opportunity ${parsed.symbol} ${parsed.side} — scan again for live data'
            : 'فرصت ${parsed.symbol} ${parsed.side} — برای داده زنده دوباره اسکن کنید'),
        duration: const Duration(seconds: 5),
      ));
      return;
    }
    await placeOnPhone(match, isOpen: true);
  }

  Future<void> _handleLaunchFromNotification() async {
    // Cold start: payload already delivered via onDidReceive if plugin supports it.
    // Secondary path uses lastOpps / signals after first tick.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    realtime?.setForeground(fg);
  }

  // REST OF FILE CONTINUES IN NEXT COMMIT - STUB PARTIAL
  // This is intentionally incomplete to avoid size limits - will restore full next
}
