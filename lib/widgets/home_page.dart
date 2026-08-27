import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/market_data.dart';
import '../services/account_balance.dart';
import '../services/ai_analyst.dart';
import '../services/futures_execution_service.dart';
import '../services/live_trading_gate.dart';
import '../services/paper_journal_resolver.dart';
import '../services/local_trade_store.dart';
import '../services/order_sizing.dart';
import '../services/position_tracker.dart';
import '../services/realtime_futures_scanner_service.dart';
import '../services/android_notification_service.dart';
import '../services/fcm_opportunity_payload.dart';
import '../main.dart' show appPush;
import '../services/push_open_handler.dart';
import '../services/tradingview_signal_service.dart';
import '../services/scanner_service.dart';
import '../services/signal_cooldown.dart';
import '../services/signal_journal.dart';
import '../services/symbol_rules_service.dart';
import '../services/tabdeal_api.dart';
import '../services/tabdeal_trade.dart';
import 'account_page.dart';
import 'ai_performance_page.dart';
import 'connection_diagnose_page.dart';
import 'market_chart_page.dart';
import 'trade_settings_page.dart';
import 'wallet_page.dart';

const ownerUsername = 'Siavashmorad';

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  /// Optional FCM / cold-start payload. Never auto-orders.
  final FcmOpportunityPayload? pendingPush;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
    this.aiUsername,
    this.aiPassword,
    this.pendingPush,
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
  final tvSignals = TradingViewSignalService();
  Timer? _tvPollTimer;
  String tvStatusLabel = '';
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
  final _pushHandler = PushOpenHandler();
  StreamSubscription<FcmOpportunityPayload>? _pushSub;
  bool _handlingPush = false;
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
    _pushSub = appPush.opportunityOpened.listen((p) {
      // ignore: discarded_futures
      _handleFcmOpportunity(p);
    });
    if (widget.pendingPush != null) {
      // ignore: discarded_futures
      Future.microtask(() => _handleFcmOpportunity(widget.pendingPush!));
    }
    _checkTabdeal();
    _refreshTradeStatus();
  }

  Future<void> _onNotificationTap(String? payload) async {
    final fcm = FcmOpportunityPayload.fromLocalPayload(payload);
    if (fcm != null) {
      await _handleFcmOpportunity(fcm);
      return;
    }
    final parsed = AndroidNotificationService.parsePayload(payload);
    if (parsed == null) return;
    await _handleFcmOpportunity(FcmOpportunityPayload(
      type: 'signal_opportunity',
      opportunityId: '${parsed.symbol}|${parsed.side}',
      symbol: parsed.symbol,
      side: parsed.side,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// FCM open → live rescan → revalidate → placeOnPhone. Never auto-orders.
  Future<void> _handleFcmOpportunity(FcmOpportunityPayload payload) async {
    if (_handlingPush) return;
    _handlingPush = true;
    final en = widget.english;
    try {
      if (!mounted) return;
      MarketSignal? live;
      try {
        live = await scanner.scanSymbol(payload.symbol, duration);
      } catch (_) {
        live = null;
      }
      if (live == null) {
        for (final s in signals) {
          if (s.symbol.toUpperCase() == payload.symbol &&
              s.side.toUpperCase() == payload.side) {
            live = s;
            break;
          }
        }
      }
      final result = _pushHandler.evaluate(payload: payload, live: live);
      if (!mounted) return;
      if (result.decision == PushOpenDecision.reject) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(en ? 'Opportunity expired' : 'فرصت منقضی'),
            content: Text(en ? result.reasonEn : result.reasonFa),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(en ? 'OK' : 'باشه'),
              ),
            ],
          ),
        );
        return;
      }
      final signal = result.liveSignal;
      if (signal == null) return;
      await placeOnPhone(signal, isOpen: true);
    } finally {
      _handlingPush = false;
    }
  }

  Future<void> _handleLaunchFromNotification() async {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    realtime?.setForeground(fg);
  }

  Future<void> _refreshTvHints() async {
    if (!tvSignals.enabled || tvSignals.baseUrl.trim().isEmpty) {
      realtime?.externalHints = const {};
      if (mounted) {
        setState(() {
          tvStatusLabel = widget.english ? 'TV: OFF' : 'TV: خاموش';
        });
      }
      return;
    }
    try {
      final alerts = await tvSignals.fetchAlerts();
      final hints = <String, String>{};
      for (final a in alerts) {
        if (a.isActionable) hints[a.symbol] = a.signal;
      }
      realtime?.externalHints = hints;
      if (!mounted) return;
      setState(() {
        if (hints.isEmpty) {
          tvStatusLabel = widget.english
              ? 'TV: CONNECTED (no fresh alerts)'
              : 'TV: وصل (هشدار تازه نیست)';
        } else {
          tvStatusLabel = widget.english
              ? 'TV: CONNECTED (${hints.length} hints)'
              : 'TV: وصل (${hints.length} راهنما)';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        tvStatusLabel = widget.english ? 'TV: DEGRADED' : 'TV: ضعیف';
      });
    }
  }

  Future<void> _syncRealtime(bool enable) async {
    if (enable) {
      realtime ??= RealtimeFuturesScannerService(
        scanner: scanner,
        journal: signalJournal,
        onOpportunities: (list) {
          if (!mounted) return;
          final mapped = list.map((e) => e.signal).toList();
          setState(() {
            signals = mapped;
            marketCount = mapped.map((e) => e.symbol).toSet().length;
            final src = scanner.dataSource;
            status = mapped.isEmpty
                ? (widget.english
                    ? 'NO VALID OPPORTUNITY ($src)'
                    : 'فرصت معتبری نیست ($src)')
                : (widget.english
                    ? '${mapped.length} live opportunities'
                    : '${mapped.length} فرصت زنده');
          });
        },
        onNotify: (opp, body) {
          if (!mounted) return;
          if (realtimeNotify) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(body),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: widget.english ? 'Open' : 'باز کردن',
                  onPressed: () => placeOnPhone(opp.signal, isOpen: true),
                ),
              ),
            );
          }
          if (androidOsNotify) {
            final s = opp.signal;
            // ignore: discarded_futures
            androidNotify.showOpportunity(
              id: s.symbol.hashCode & 0x7fffffff,
              title: widget.english
                  ? 'SignalYab Futures Opportunity'
                  : 'فرصت فیوچرز سیگنال‌یاب',
              body: body,
              payload: AndroidNotificationService.payloadFor(
                symbol: s.symbol,
                side: s.side,
              ),
            );
          }
        },
        onState: (s, detail) {
          if (!mounted) return;
          setState(() {
            realtimeLabel =
                '${realtimeScannerStateLabel(s, english: widget.english)} · $detail';
          });
        },
      );
      realtime!.timeframe = duration;
      realtime!.foreground = true;
      final prefsRt = await SharedPreferences.getInstance();
      realtime!.allowBackgroundPolling =
          prefsRt.getBool('realtime_background_polling') ?? true;
      final minQ = prefsRt.getString('realtime_notify_min_quality') ?? 'A';
      realtime!.notifications.minQualityForNotify = minQ;
      final tvOn = prefsRt.getBool('tradingview_enabled') ?? false;
      final tvUrl = prefsRt.getString('tradingview_backend_url') ?? '';
      tvSignals.enabled = tvOn;
      tvSignals.baseUrl = tvUrl;
      tvSignals.username =
          prefsRt.getString('signalyab_username') ?? ownerUsername;
      tvSignals.password =
          prefsRt.getString('signalyab_backend_password') ?? '';
      await _refreshTvHints();
      _tvPollTimer?.cancel();
      _tvPollTimer = Timer.periodic(const Duration(seconds: 90), (_) {
        // ignore: discarded_futures
        _refreshTvHints();
      });
      await realtime!.start();
    } else {
      _tvPollTimer?.cancel();
      _tvPollTimer = null;
      realtime?.stop();
      if (mounted) {
        setState(() => tvStatusLabel = '');
      }
    }
  }

  Future<void> _refreshTradeStatus() async {
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    final p = await SharedPreferences.getInstance();
    final prefer = p.getBool('prefer_futures_execution') ?? false;
    final rt = p.getBool('realtime_futures_scanner') ?? false;
    final notify = p.getBool('realtime_notify') ?? true;
    final osNotify = p.getBool('android_os_notify') ?? true;
    if (!mounted) return;
    setState(() {
      liveOn = live && has;
      preferFutures = prefer;
      realtimeOn = rt;
      realtimeNotify = notify;
      androidOsNotify = osNotify;
    });
    androidNotify.enabled = osNotify;
    await _syncRealtime(rt);
  }

  Future<void> _openDiagnose() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ConnectionDiagnosePage(english: widget.english, api: api),
    ));
    await _checkTabdeal();
  }

  Future<void> _openChart(MarketSignal s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MarketChartPage(
        signal: s,
        api: api,
        english: widget.english,
        lastOrderFill: lastFills[s.symbol],
      ),
    ));
  }

  Future<void> _checkTabdeal() async {
    setState(() => checkingLink = true);
    final ok = await api.ping();
    if (!mounted) return;
    setState(() {
      tabdealLinked = ok;
      checkingLink = false;
      status = ok
          ? (widget.english
              ? 'Tabdeal OK (${api.activeHost})'
              : 'تبدیل وصل است (${api.activeHost})')
          : (widget.english
              ? 'Tabdeal offline — tap to diagnose'
              : 'تبدیل قطع — برای تست بزنید');
    });
  }

  Future<void> scan() async {
    if (loading) return;
    setState(() {
      loading = true;
      status = widget.english ? 'Scanning...' : 'در حال اسکن...';
    });
    final started = DateTime.now();
    try {
      final result = await scanner.scanAll(
        timeframe: duration,
        maxConcurrency: 8,
        maxSymbols: 20,
        maxSignals: 12,
      );
      final secs = DateTime.now().difference(started).inSeconds;
      final src = scanner.dataSource;
      if (!mounted) return;
      final filtered = signalCooldown.filter(result);
      for (final s in filtered) {
        await signalJournal.record(JournalEntry.fromSignal(
          s,
          regime: 'UNKNOWN',
          quality: s.confidence >= 85
              ? 'A+'
              : s.confidence >= 72
                  ? 'A'
                  : s.confidence >= 58
                      ? 'B'
                      : 'C',
          score: s.confidence,
          confidence: s.confidence,
          reasons: 'scanner',
          mode: JournalMode.paper,
        ));
      }
      try {
        await PaperJournalResolver(api: api).resolvePending(signalJournal);
      } catch (_) {}
      setState(() {
        signals = filtered;
        marketCount = filtered.map((e) => e.symbol).toSet().length;
        loading = false;
        tabdealLinked = src == 'tabdeal' || tabdealLinked;
        final srcLabel = src == 'tabdeal'
            ? (widget.english ? 'Tabdeal' : 'تبدیل')
            : src == 'binance'
                ? (widget.english ? 'Binance fallback' : 'پشتیبان بایننس')
                : '?';
        status = filtered.isEmpty
            ? (widget.english
                ? 'No setup (${secs}s) via $srcLabel'
                : 'سیگنال نبود ($secsث) از $srcLabel')
            : (widget.english
                ? '${filtered.length} setups in ${secs}s ($srcLabel)'
                : '${filtered.length} فرصت در $secsث ($srcLabel)');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        status = e.toString().replaceFirst('TabdealApiException: ', '');
      });
    }
  }

  Future<void> analyzeWithAi(MarketSignal signal) async {
    if (aiLoading) return;
    setState(() {
      selectedForAi = signal;
      aiAnalysis = null;
      aiError = null;
      aiLoading = true;
    });
    try {
      final result = await ai.analyze(
        signal: signal,
        username: widget.aiUsername ?? ownerUsername,
        password: widget.aiPassword ?? 'local',
      );
      if (!mounted) return;
      setState(() {
        aiAnalysis = result;
        aiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        aiLoading = false;
        aiError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> placeOnPhone(MarketSignal signal, {required bool isOpen}) async {
    final en = widget.english;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('emergency_stop') ?? false) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'EMERGENCY STOP ACTIVE — orders blocked'
            : 'توقف اضطراری فعال — سفارش مسدود'),
      ));
      return;
    }
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!has || !live) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'Open wallet settings: API key + LIVE'
            : 'تنظیمات کیف پول: کلید API + سفارش واقعی'),
      ));
      return;
    }
    if ((prefs.getBool('prefer_futures_execution') ?? false) && isOpen) {
      await _placeFuturesOnPhone(signal);
      return;
    }
    // Resolve pending paper trades before Live Gate (SPOT).
    await PaperJournalResolver(api: api).resolvePending(signalJournal);
    final journal = await signalJournal.load();
    final q = signal.confidence >= 85
        ? 'A+'
        : signal.confidence >= 72
            ? 'A'
            : signal.confidence >= 58
                ? 'B'
                : 'C';
    final gate = liveGate.evaluate(
      journal: journal,
      quality: q,
      regime: 'UNKNOWN',
      userLiveEnabled: live,
      dataHealthy: tabdealLinked,
    );
    if (!gate.allowLive) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'LIVE GATE' : 'قفل معامله زنده'),
          content: Text(gate.reason),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(en ? 'OK' : 'باشه')),
          ],
        ),
      );
      return;
    }
    final configured = await tradeStore.defaultQty();
    final filters = await rules.filtersFor(signal.symbol);
    final isLong = signal.side.toUpperCase() == 'LONG';
    final side = isOpen ? (isLong ? 'BUY' : 'SELL') : (isLong ? 'SELL' : 'BUY');
    final isBuy = side == 'BUY';
    final client = TabdealTradeClient(
      apiKey: await tradeStore.apiKey(),
      apiSecret: await tradeStore.apiSecret(),
    );
    final snap = await client.accountSnapshot();
    final quote = AccountSnapshot.quoteAsset(signal.symbol);
    final available = snap.available
        ? (isBuy ? snap.freeQuote(signal.symbol) : snap.freeBase(signal.symbol))
        : 0.0;
    final size = sizing.compute(
      filters: filters,
      configuredQty: configured,
      currentPrice: signal.entry,
      availableQuote: isBuy ? available : (available * signal.entry),
      riskPercent: 0.01,
      entry: signal.entry,
      stopLoss: signal.stopLoss,
      isBuy: isBuy,
    );
    if (!size.canSubmit) {
      client.dispose();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'NO TRADE' : 'بدون معامله'),
          content: Text(
            '${size.message}\n\n'
            '${en ? 'Balance' : 'موجودی'} $quote: '
            '${snap.available ? available.toStringAsFixed(4) : (snap.error ?? 'Unavailable')}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(en ? 'OK' : 'باشه')),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(en ? 'Approve SPOT order' : 'تأیید سفارش اسپات'),
        content: SingleChildScrollView(
          child: Text(
            '${signal.symbol}\n'
            '${en ? 'Action' : 'عملیات'}: SPOT $side\n'
            '${en ? 'Side' : 'جهت'}: ${signal.side}\n'
            '${en ? 'Entry' : 'ورود'}: ${money(signal.entry)}\n'
            '${en ? 'SL' : 'حد ضرر'}: ${money(signal.stopLoss)}\n'
            '${en ? 'TP1' : 'هدف ۱'}: ${money(signal.tp1)}\n'
            '${en ? 'Available' : 'موجودی آزاد'} ($quote): ${available.toStringAsFixed(4)}\n'
            '${en ? 'Final qty' : 'حجم نهایی'}: ${size.finalQty}\n'
            '${size.message}\n\n'
            '${en ? 'Spot only. No guaranteed profit.' : 'فقط اسپات. سود تضمینی نیست.'}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(en ? 'Cancel' : 'لغو')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(en ? 'Confirm & send' : 'تأیید و ارسال سفارش')),
        ],
      ),
    );
    if (ok != true) {
      client.dispose();
      return;
    }
    try {
      final res = await client.marketOrder(
        symbol: signal.symbol,
        side: side,
        quantity: size.finalQty,
      );
      final tracked = TrackedOrder.fromApi(res, fallbackSymbol: signal.symbol);
      lastFills[signal.symbol] = res;
      await signalJournal.record(JournalEntry.fromSignal(
        signal,
        quality: q,
        score: signal.confidence,
        confidence: signal.confidence,
        reasons: 'live fill ${tracked.orderId ?? ''}',
        mode: JournalMode.live,
        isLive: true,
      ));
      client.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '${en ? 'SPOT' : 'اسپات'} ${tracked.rawStatus} '
          'id=${tracked.orderId ?? '-'}',
        ),
      ));
    } catch (e) {
      client.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Bad state: ', '')),
      ));
    }
  }

  Future<void> _placeFuturesOnPhone(MarketSignal signal) async {
    final en = widget.english;
    // Resolve pending paper trades before Live Gate (FUTURES).
    await PaperJournalResolver(api: api).resolvePending(signalJournal);
    final journal = await signalJournal.load();
    final q = signal.confidence >= 85
        ? 'A+'
        : signal.confidence >= 72
            ? 'A'
            : signal.confidence >= 58
                ? 'B'
                : 'C';
    final gate = liveGate.evaluate(
      journal: journal,
      quality: q,
      regime: 'UNKNOWN',
      userLiveEnabled: true,
      dataHealthy: tabdealLinked,
    );
    if (!gate.allowLive) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'LIVE GATE' : 'قفل معامله زنده'),
          content: Text(gate.reason),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(en ? 'OK' : 'باشه')),
          ],
        ),
      );
      return;
    }
    final client = TabdealTradeClient(
      apiKey: await tradeStore.apiKey(),
      apiSecret: await tradeStore.apiSecret(),
    );
    final exec = FuturesExecutionService(client);
    final filters = await rules.filtersFor(signal.symbol);
    final entry = signal.entry;
    if (entry <= 0) {
      client.dispose();
      return;
    }
    final sl = signal.stopLoss > 0
        ? signal.stopLoss
        : (signal.side.toUpperCase() == 'SHORT' ? entry * 1.01 : entry * 0.99);
    final plan = await exec.buildPlan(
      symbol: signal.symbol,
      side: signal.side,
      entry: entry,
      stopLoss: sl,
      takeProfit: signal.tp1 > 0 ? signal.tp1 : null,
      riskPercent: 1.0,
      leverage: 5,
      filters: filters,
    );
    if (plan == null || !plan.size.allow) {
      client.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(plan?.size.reason ??
            (en ? 'Futures unavailable' : 'فیوچرز در دسترس نیست')),
      ));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final autoXfer = prefs.getBool('auto_transfer_futures') ?? false;
    final needConfirm = plan.needsTransfer ? !autoXfer : true;
    if (needConfirm) {
      final sideLabel = plan.side.toUpperCase() == 'SHORT' ? 'SHORT' : 'LONG';
      final xferLine = plan.needsTransfer && plan.transferAmount > 0
          ? (en
              ? 'Transfer Spot→Futures: ${plan.transferAmount.toStringAsFixed(4)}\n'
              : 'انتقال اسپات→فیوچرز: ${plan.transferAmount.toStringAsFixed(4)}\n')
          : (en ? 'No transfer needed\n' : 'نیازی به انتقال نیست\n');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(en ? 'Open FUTURES position' : 'باز کردن پوزیشن FUTURES'),
          content: SingleChildScrollView(
            child: Text(
              '${plan.symbol}\n'
              '${en ? 'Side' : 'جهت'}: $sideLabel\n'
              '${en ? 'Entry' : 'ورود'}: ${money(plan.entry)}\n'
              '${en ? 'Qty' : 'حجم'}: ${plan.size.quantity}\n'
              '${en ? 'Leverage' : 'اهرم'}: ${plan.leverage.toStringAsFixed(0)}x\n'
              '${en ? 'Required margin' : 'وجه موردنیاز'}: ${plan.size.requiredMargin.toStringAsFixed(4)}\n'
              '${en ? 'Futures available' : 'موجودی فیوچرز'}: ${plan.futuresAvailable.toStringAsFixed(4)}\n'
              '${en ? 'Spot free' : 'اسپات آزاد'}: ${plan.spotFree.toStringAsFixed(4)}\n'
              '$xferLine'
              '${en ? 'SL' : 'حد ضرر'}: ${money(plan.stopLoss)}\n'
              '${en ? 'TP' : 'هدف'}: ${plan.takeProfit != null ? money(plan.takeProfit!) : '-'}\n'
              '${en ? 'Risk' : 'ریسک'}: ${plan.size.riskAmount.toStringAsFixed(4)}\n'
              '${en ? 'AI Quality' : 'کیفیت'}: $q\n'
              '${en ? 'AI Score' : 'امتیاز'}: ${signal.confidence.toStringAsFixed(0)}\n'
              '${en ? 'Gate' : 'گیت'}: PASS\n\n'
              '${en ? 'Only exact required margin. No guaranteed profit.' : 'فقط حاشیه دقیق. سود تضمینی نیست.'}',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(en ? 'Cancel' : 'لغو')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    Text(en ? 'Confirm & send order' : 'تأیید و ارسال سفارش')),
          ],
        ),
      );
      if (ok != true) {
        client.dispose();
        return;
      }
    }
    final result = await exec.execute(plan);
    client.dispose();
    if (!mounted) return;
    final slL = result.slActive
        ? (en ? 'SL: ACTIVE' : 'SL: فعال')
        : (en ? 'SL: NOT CONFIRMED' : 'SL: تأیید نشد');
    final tpL = result.tpActive
        ? (en ? 'TP: ACTIVE' : 'TP: فعال')
        : (en ? 'TP: NOT CONFIRMED' : 'TP: تأیید نشد');
    final posL = result.ok && result.position != null
        ? (en ? 'POSITION OPENED' : 'POSITION OPENED — پوزیشن باز شد')
        : (result.ok
            ? (en ? 'ORDER SENT' : 'سفارش ارسال شد')
            : (en ? 'POSITION NOT CONFIRMED' : 'POSITION NOT CONFIRMED'));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.ok
            ? (en ? 'FUTURES RESULT' : 'نتیجه فیوچرز')
            : (en ? 'FUTURES FAILED' : 'فیوچرز ناموفق')),
        content: Text('${result.message}\n$posL\n$slL\n$tpL'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(en ? 'OK' : 'باشه')),
        ],
      ),
    );
  }

  String money(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(5);
    return value.toStringAsFixed(8);
  }

  String _openButtonLabel(MarketSignal s, bool en) {
    final side = s.side.toUpperCase() == 'SHORT' ? 'SHORT' : 'LONG';
    if (preferFutures) {
      return en ? 'Open FUTURES — $side' : 'باز کردن پوزیشن FUTURES — $side';
    }
    return en ? 'Execute SPOT order' : 'اجرای سفارش SPOT';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushSub?.cancel();
    _tvPollTimer?.cancel();
    _tvPollTimer = null;
    realtime?.dispose();
    tvSignals.dispose();
    ai.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'SignalYab' : 'سیگنال‌یاب'),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AiPerformancePage(english: en),
                ));
              },
              icon: const Icon(Icons.analytics_outlined),
            ),
            IconButton(
              tooltip: en ? 'Wallet' : 'کیف پول',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WalletPage(english: en),
                ));
              },
              icon: const Icon(Icons.account_balance_wallet),
            ),
            IconButton(
              tooltip: en ? 'Account' : 'حساب',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AccountPage(
                    english: en,
                    currentUsername: widget.aiUsername ?? ownerUsername,
                    onLogout: widget.onLogout,
                  ),
                ));
                await _refreshTradeStatus();
              },
              icon: const Icon(Icons.person_outline),
            ),
            IconButton(
              onPressed: _openDiagnose,
              icon: const Icon(Icons.network_check),
            ),
            IconButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TradeSettingsPage(english: en),
                ));
                await _refreshTradeStatus();
              },
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              onPressed: widget.onTheme,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
                onPressed: widget.onLang, icon: const Icon(Icons.language)),
            IconButton(
                onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: scan,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: tabdealLinked
                    ? Colors.green.withOpacity(0.08)
                    : Colors.orange.withOpacity(0.08),
                child: ListTile(
                  onTap: _openDiagnose,
                  leading: checkingLink
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          tabdealLinked ? Icons.link : Icons.link_off,
                          color: tabdealLinked ? Colors.green : Colors.orange,
                        ),
                  title: Text(checkingLink
                      ? (en ? 'Checking...' : 'در حال تست...')
                      : (tabdealLinked
                          ? (en ? 'Tabdeal connected' : 'تبدیل متصل')
                          : (en ? 'Tabdeal offline' : 'تبدیل قطع'))),
                  subtitle: Text(status ?? ''),
                ),
              ),
              if (realtimeOn)
                Card(
                  color: Colors.blue.withOpacity(0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          en ? 'FUTURES MARKET WATCHER' : 'پایش بازار فیوچرز',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(realtimeLabel.isEmpty
                            ? (en ? 'MONITORING' : 'پایش')
                            : realtimeLabel),
                        if (tvStatusLabel.isNotEmpty)
                          Text(
                            tvStatusLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        if (realtime != null) ...[
                          Text(
                            en
                                ? 'Scanned: ${realtime!.lastScannedCount} markets'
                                : 'اسکن‌شده: ${realtime!.lastScannedCount} بازار',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (realtime!.lastSuccess != null)
                            Text(
                              en
                                  ? 'Last update: ${realtime!.lastSuccess!.toLocal().toString().substring(0, 19)}'
                                  : 'آخرین به‌روز: ${realtime!.lastSuccess!.toLocal().toString().substring(0, 19)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                        const SizedBox(height: 8),
                        if (signals.isEmpty)
                          Text(
                            en
                                ? 'NO VALID OPPORTUNITY'
                                : 'فرصت معتبری پیدا نشد',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )
                        else ...[
                          Text(
                            en
                                ? 'Best: ${signals.first.symbol} ${signals.first.side}'
                                : 'بهترین: ${signals.first.symbol} ${signals.first.side}',
                          ),
                          Text(
                            'Score: ${signals.first.confidence.toStringAsFixed(0)}  '
                            'R/R: 1:${signals.first.riskReward.toStringAsFixed(1)}',
                          ),
                          Text(
                            'E=${money(signals.first.entry)}  '
                            'SL=${money(signals.first.stopLoss)}  '
                            'TP1=${money(signals.first.tp1)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () =>
                                placeOnPhone(signals.first, isOpen: true),
                            child: Text(_openButtonLabel(signals.first, en)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: timeframe,
                              decoration: InputDecoration(
                                labelText: en ? 'Timeframe' : 'تایم‌فریم',
                              ),
                              items: ['1m', '5m', '15m', '1h']
                                  .map((x) => DropdownMenuItem(
                                      value: x, child: Text(x)))
                                  .toList(),
                              onChanged: loading
                                  ? null
                                  : (v) {
                                      setState(
                                          () => timeframe = v ?? timeframe);
                                      if (realtime != null) {
                                        realtime!.timeframe = duration;
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: loading ? null : scan,
                              icon: const Icon(Icons.radar),
                              label: Text(
                                  loading ? '...' : (en ? 'Scan' : 'اسکن')),
                            ),
                          ),
                        ],
                      ),
                      if (liveOn)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            en
                                ? (preferFutures
                                    ? 'LIVE + FUTURES mode — gate requires paper sample'
                                    : 'LIVE + SPOT mode — gate requires paper sample')
                                : (preferFutures
                                    ? 'زنده + فیوچرز — گیت نیاز به نمونه پیپر دارد'
                                    : 'زنده + اسپات — گیت نیاز به نمونه پیپر دارد'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (signals.isNotEmpty) ...[
                Text(
                  en
                      ? 'Opportunities ($marketCount)'
                      : 'فرصت‌ها ($marketCount)',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                ...signals.take(10).map(
                      (s) => Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${s.symbol} ${s.side}'),
                                subtitle: Text(
                                  'E=${money(s.entry)} SL=${money(s.stopLoss)} '
                                  'TP1=${money(s.tp1)} RR=1:${s.riskReward.toStringAsFixed(1)}\n'
                                  'conf=${s.confidence.toStringAsFixed(0)}',
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: en ? 'Chart' : 'نمودار',
                                      onPressed: () => _openChart(s),
                                      icon: const Icon(Icons.show_chart),
                                    ),
                                    IconButton(
                                      tooltip: en ? 'AI' : 'تحلیل',
                                      onPressed: () => analyzeWithAi(s),
                                      icon: const Icon(Icons.psychology),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              FilledButton.icon(
                                onPressed: () => placeOnPhone(s, isOpen: true),
                                icon: Icon(
                                  preferFutures
                                      ? Icons.candlestick_chart
                                      : Icons.shopping_cart_checkout,
                                ),
                                label: Text(
                                  _openButtonLabel(s, en),
                                  textAlign: TextAlign.center,
                                ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
              if (selectedForAi != null || aiLoading || aiError != null)
                Card(
                  child: ListTile(
                    title: Text(en ? 'AI' : 'تحلیل'),
                    subtitle: Text(aiLoading
                        ? '...'
                        : (aiError ??
                            (aiAnalysis?.summary ??
                                selectedForAi?.symbol ??
                                ''))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
