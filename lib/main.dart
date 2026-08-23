import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/market_data.dart';
import 'services/ai_analyst.dart';
import 'services/execution_service.dart';
import 'services/scanner_service.dart';
import 'services/tabdeal_api.dart';
import 'widgets/execution_panel.dart';

const ownerUsername = 'Siavashmorad';

void main() => runApp(const SignalApp());

class SignalApp extends StatefulWidget {
  const SignalApp({super.key});
  @override
  State<SignalApp> createState() => _SignalAppState();
}

class _SignalAppState extends State<SignalApp> {
  bool dark = false, english = false, logged = false, ready = false;
  String? sessionUsername;
  String? sessionPassword;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      logged = prefs.getBool('logged') ?? false;
      ready = true;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', false);
    if (mounted) {
      setState(() {
        logged = false;
        sessionUsername = null;
        sessionPassword = null;
      });
    }
  }

  void _login(String username, String password) {
    setState(() {
      sessionUsername = username;
      sessionPassword = password;
      logged = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: logged
          ? HomePage(
              english: english,
              dark: dark,
              aiUsername: sessionUsername,
              aiPassword: sessionPassword,
              onLang: () => setState(() => english = !english),
              onTheme: () => setState(() => dark = !dark),
              onLogout: _logout,
            )
          : LoginPage(english: english, onLogin: _login),
    );
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF5B4BDB),
        inputDecorationTheme:
            const InputDecorationTheme(border: OutlineInputBorder()),
        cardTheme: const CardTheme(margin: EdgeInsets.symmetric(vertical: 6)),
      );
}

class LoginPage extends StatefulWidget {
  final bool english;
  final void Function(String username, String password) onLogin;
  const LoginPage({super.key, required this.english, required this.onLogin});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController(text: ownerUsername);
  final password = TextEditingController();
  String? error;

  Future<void> login() async {
    if (username.text.trim() != ownerUsername || password.text.length < 6) {
      setState(() => error = widget.english
          ? 'Username or password is invalid.'
          : 'نام کاربری یا رمز عبور صحیح نیست.');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged', true);
    widget.onLogin(username.text.trim(), password.text);
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        child: Icon(Icons.candlestick_chart, size: 40),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'سیگنال‌یاب',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.english
                            ? 'Live Tabdeal scanner + on-device analyst'
                            : 'اتصال زنده به تبدیل + تحلیلگر روی گوشی',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: username,
                        decoration: InputDecoration(
                          labelText: widget.english ? 'Username' : 'نام کاربری',
                          prefixIcon: const Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: widget.english ? 'Password' : 'رمز عبور',
                          prefixIcon: const Icon(Icons.lock),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: login,
                          icon: const Icon(Icons.login),
                          label: Text(widget.english ? 'Sign in' : 'ورود'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  final bool english, dark;
  final String? aiUsername, aiPassword;
  final VoidCallback onLang, onTheme, onLogout;
  const HomePage({
    super.key,
    required this.english,
    required this.dark,
    required this.aiUsername,
    required this.aiPassword,
    required this.onLang,
    required this.onTheme,
    required this.onLogout,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final api = TabdealApi();
  late final scanner = ScannerService(api);
  final ai = AiAnalystService();
  final execution = ExecutionService();
  final history = <MarketSignal>[];
  bool loading = false;
  bool checkingLink = true;
  bool tabdealLinked = false;
  String timeframe = '15m';
  String? status;
  List<MarketSignal> signals = [];
  int marketCount = 0;
  MarketSignal? selectedForAi;
  AiAnalysis? aiAnalysis;
  bool aiLoading = false;
  String? aiError;
  int pendingRefreshToken = 0;

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
              ? 'Connected to Tabdeal (${api.activeHost})'
              : 'متصل به تبدیل (${api.activeHost})')
          : (widget.english
              ? 'Cannot reach Tabdeal. Check mobile data/Wi-Fi.'
              : 'اتصال به تبدیل برقرار نشد. اینترنت را چک کنید.');
    });
  }

  Future<void> scan() async {
    if (loading) return;
    setState(() {
      loading = true;
      status = widget.english
          ? 'Scanning top USDT markets on Tabdeal...'
          : 'در حال اسکن سریع بازارهای مهم USDT روی تبدیل...';
    });
    final started = DateTime.now();
    try {
      final result = await scanner.scanAll(
        timeframe: duration,
        maxConcurrency: 10,
        maxSymbols: 30,
        maxSignals: 12,
      );
      final secs = DateTime.now().difference(started).inSeconds;
      if (!mounted) return;
      setState(() {
        signals = result;
        marketCount = result.map((e) => e.symbol).toSet().length;
        loading = false;
        tabdealLinked = true;
        status = result.isEmpty
            ? (widget.english
                ? 'Connected. No setup matched filters (${secs}s).'
                : 'متصل شد. در $secs ثانیه سیگنال تأییدشده‌ای پیدا نشد.')
            : (widget.english
                ? '${result.length} setups in ${secs}s via ${api.activeHost}'
                : '${result.length} فرصت در ${secs}ث از ${api.activeHost}');
        for (final item in result.take(20)) {
          if (!history.any((h) =>
              h.symbol == item.symbol &&
              h.timestamp.difference(item.timestamp).inMinutes.abs() < 2)) {
            history.add(item);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        tabdealLinked = false;
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

  Future<void> proposeOpen(MarketSignal signal) async {
    final en = widget.english;
    if (!execution.configured) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(en
            ? 'Trading backend not in this APK (scan+analyst work).'
            : 'بک‌اند معامله در این APK نیست؛ اسکن و تحلیل کار می‌کند.'),
      ));
      return;
    }
    if (widget.aiUsername == null || widget.aiPassword == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(en ? 'Request OPEN' : 'درخواست باز کردن'),
        content: Text('${signal.symbol} ${signal.side}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(en ? 'Cancel' : 'انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(en ? 'Propose' : 'ثبت')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await execution.proposeOpen(
        username: widget.aiUsername!,
        password: widget.aiPassword!,
        symbol: signal.symbol,
        side: signal.side,
        quantity: 0.001,
        entry: signal.entry,
        stopLoss: signal.stopLoss,
        takeProfit: signal.tp1,
      );
      if (mounted) setState(() => pendingRefreshToken++);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
        );
      }
    }
  }

  Future<void> proposeClose(MarketSignal signal) async {
    if (!execution.configured ||
        widget.aiUsername == null ||
        widget.aiPassword == null) {
      return;
    }
    try {
      await execution.proposeClose(
        username: widget.aiUsername!,
        password: widget.aiPassword!,
        symbol: signal.symbol,
      );
      if (mounted) setState(() => pendingRefreshToken++);
    } catch (_) {}
  }

  String money(double value) {
    if (value >= 1000) return value.toStringAsFixed(2);
    if (value >= 1) return value.toStringAsFixed(5);
    return value.toStringAsFixed(8);
  }

  @override
  void dispose() {
    ai.dispose();
    execution.dispose();
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
              onPressed: checkingLink ? null : _checkTabdeal,
              icon: Icon(
                tabdealLinked ? Icons.cloud_done : Icons.cloud_off,
                color: checkingLink
                    ? null
                    : (tabdealLinked ? Colors.green : Colors.red),
              ),
            ),
            IconButton(
              onPressed: widget.onTheme,
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              onPressed: widget.onLang,
              icon: const Icon(Icons.language),
            ),
            IconButton(
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
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
                      ? (en ? 'Checking Tabdeal...' : 'در حال اتصال به تبدیل...')
                      : (tabdealLinked
                          ? (en ? 'Live on Tabdeal' : 'متصل به تبدیل (زنده)')
                          : (en ? 'Offline from Tabdeal' : 'قطع از تبدیل'))),
                  subtitle: Text(status ?? ''),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        en ? 'Fast USDT scanner' : 'اسکن سریع USDT',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(en
                          ? 'Top ~30 liquid markets from Tabdeal.'
                          : 'حدود ۳۰ بازار نقدشونده از تبدیل.'),
                      const SizedBox(height: 16),
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
                              label: Text(loading
                                  ? '...'
                                  : (en ? 'Scan' : 'اسکن')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ExecutionPanel(
                key: ValueKey(pendingRefreshToken),
                english: en,
                username: widget.aiUsername,
                password: widget.aiPassword,
                execution: execution,
              ),
              if (signals.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    en
                        ? 'Best opportunities ($marketCount)'
                        : 'بهترین فرصت‌ها ($marketCount)',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ...signals.take(10).map(
                      (signal) => _SignalCard(
                        signal: signal,
                        en: en,
                        money: money,
                        onAi: () => analyzeWithAi(signal),
                        onProposeOpen: () => proposeOpen(signal),
                        onProposeClose: () => proposeClose(signal),
                      ),
                    ),
              ],
              if (selectedForAi != null || aiLoading || aiError != null)
                _AiAnalysisCard(
                  en: en,
                  signal: selectedForAi,
                  analysis: aiAnalysis,
                  loading: aiLoading,
                  error: aiError,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  final MarketSignal signal;
  final bool en;
  final String Function(double) money;
  final VoidCallback? onAi;
  final VoidCallback? onProposeOpen;
  final VoidCallback? onProposeClose;

  const _SignalCard({
    required this.signal,
    required this.en,
    required this.money,
    required this.onAi,
    required this.onProposeOpen,
    required this.onProposeClose,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    signal.symbol,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Chip(label: Text(signal.side)),
                ],
              ),
              const Divider(),
              _row(en ? 'Confidence' : 'اطمینان',
                  '${signal.confidence.toStringAsFixed(0)}%'),
              _row(en ? 'Entry' : 'ورود', money(signal.entry)),
              _row(en ? 'Stop Loss' : 'حد ضرر', money(signal.stopLoss)),
              _row('TP1', money(signal.tp1)),
              _row('TP2', money(signal.tp2)),
              _row(en ? 'Risk / Reward' : 'ریسک / سود',
                  '1 : ${signal.riskReward.toStringAsFixed(1)}'),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onAi,
                  icon: const Icon(Icons.psychology),
                  label: Text(en ? 'Analyst' : 'تحلیلگر هوشمند'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onProposeOpen,
                      icon: const Icon(Icons.lock_open),
                      label: Text(en ? 'OPEN' : 'باز'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onProposeClose,
                      icon: const Icon(Icons.lock),
                      label: Text(en ? 'CLOSE' : 'بستن'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}

class _AiAnalysisCard extends StatelessWidget {
  final bool en;
  final MarketSignal? signal;
  final AiAnalysis? analysis;
  final bool loading;
  final String? error;

  const _AiAnalysisCard({
    required this.en,
    required this.signal,
    required this.analysis,
    required this.loading,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Card(
        child: ListTile(
          leading: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(en ? 'Analyzing...' : 'در حال تحلیل...'),
        ),
      );
    }
    if (error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(en ? 'Analysis failed' : 'تحلیل ناموفق'),
          subtitle: Text(error!),
        ),
      );
    }
    final result = analysis;
    if (result == null) return const SizedBox.shrink();
    final src = result.source == 'remote'
        ? (en ? 'Cloud AI' : 'هوش ابری')
        : (en ? 'On-device analyst' : 'تحلیلگر روی گوشی');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(en ? 'Analyst' : 'تحلیلگر',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Chip(label: Text(src)),
              ],
            ),
            if (signal != null) Text('${signal!.symbol} • ${signal!.side}'),
            const SizedBox(height: 8),
            Text(result.summary),
            const Divider(),
            Text('${en ? 'Recommendation' : 'پیشنهاد'}: ${result.recommendation}'),
            Text('${en ? 'Trend' : 'روند'}: ${result.trend}'),
            Text('${en ? 'Momentum' : 'مومنتوم'}: ${result.momentum}'),
            Text('${en ? 'Risk' : 'ریسک'}: ${result.riskLevel}'),
            Text('${en ? 'Quality' : 'کیفیت'}: ${result.signalQuality}'),
            Text('${en ? 'Confidence' : 'اطمینان'}: ${result.confidence}%'),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(en ? 'Reasons' : 'دلایل',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ...result.reasons.map((r) => Text('• $r')),
            ],
          ],
        ),
      ),
    );
  }
}
