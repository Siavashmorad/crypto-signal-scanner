import 'package:flutter/material.dart';
import '../models/market_data.dart';
import '../services/account_balance.dart';
import '../services/ai_analyst.dart';
import '../services/live_trading_gate.dart';
import '../services/local_trade_store.dart';
import '../services/order_sizing.dart';
import '../services/position_tracker.dart';
import '../services/scanner_service.dart';
import '../services/signal_cooldown.dart';
import '../services/signal_journal.dart';
import '../services/symbol_rules_service.dart';
import '../services/tabdeal_api.dart';
import '../services/tabdeal_trade.dart';
import 'ai_performance_page.dart';
import 'connection_diagnose_page.dart';
import 'market_chart_page.dart';
import 'trade_settings_page.dart';

const ownerUsername = 'Siavashmorad';

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

class _HomePageState extends State<HomePage> {
  final api = TabdealApi();
  late final scanner = ScannerService(api);
  late final rules = SymbolRulesService(api);
  final sizing = OrderSizingEngine();
  final ai = AiAnalystService();
  final tradeStore = LocalTradeStore();
  final signalJournal = SignalJournal();
  final signalCooldown = SignalCooldown();
  final liveGate = LiveTradingGate();
  final Map<String, Map<String, dynamic>> lastFills = {};
  bool loading = false;
  bool checkingLink = true;
  bool tabdealLinked = false;
  bool liveOn = false;
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
    _checkTabdeal();
    _refreshTradeStatus();
  }

  Future<void> _refreshTradeStatus() async {
    final has = await tradeStore.hasKeys();
    final live = await tradeStore.liveEnabled();
    if (!mounted) return;
    setState(() => liveOn = live && has);
  }

  Future<void> _openDiagnose() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          ConnectionDiagnosePage(english: widget.english, api: api),
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
    final side = isOpen
        ? (isLong ? 'BUY' : 'SELL')
        : (isLong ? 'SELL' : 'BUY');
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
            '${en ? 'Available' : 'موجودی آزاد'} ($quote): ${available.toStringAsFixed(4)}\n'
            '${en ? 'Final qty' : 'حجم نهایی'}: ${size.finalQty}\n'
            '${size.message}\n\n'
            '${en ? 'Spot only.' : 'فقط اسپات.'}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(en ? 'Cancel' : 'انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(en ? 'Send' : 'ارسال')),
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

  String money(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(5);
    return value.toStringAsFixed(8);
  }

  @override
  void dispose() {
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
              icon: const Icon(Icons.account_balance_wallet_outlined),
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
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
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
                                  : (v) => setState(
                                      () => timeframe = v ?? timeframe),
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
                                ? 'LIVE enabled — gate requires validated paper sample'
                                : 'زنده فعال — گیت نیاز به نمونه پیپر معتبر دارد',
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
                        child: ListTile(
                          title: Text('${s.symbol} ${s.side}'),
                          subtitle: Text(
                            'E=${money(s.entry)} SL=${money(s.stopLoss)} '
                            'TP1=${money(s.tp1)} RR=1:${s.riskReward.toStringAsFixed(1)}\n'
                            'conf=${s.confidence.toStringAsFixed(0)}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                  onPressed: () => _openChart(s),
                                  icon: const Icon(Icons.show_chart)),
                              IconButton(
                                  onPressed: () => analyzeWithAi(s),
                                  icon: const Icon(Icons.psychology)),
                              IconButton(
                                  onPressed: () =>
                                      placeOnPhone(s, isOpen: true),
                                  icon: const Icon(Icons.play_arrow)),
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
