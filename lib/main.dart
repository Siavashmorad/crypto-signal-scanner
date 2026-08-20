import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/market_data.dart';
import 'services/ai_analyst.dart';
import 'services/scanner_service.dart';
import 'services/tabdeal_api.dart';

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
          : LoginPage(
              english: english,
              onLogin: _login,
            ),
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
                        'Crypto Signal Scanner',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.english
                            ? 'Private signal access'
                            : 'دسترسی خصوصی به اسکنر سیگنال',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: username,
                        decoration: InputDecoration(
                          labelText:
                              widget.english ? 'Username' : 'نام کاربری',
                          prefixIcon: const Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText:
                              widget.english ? 'Password' : 'رمز عبور',
                          prefixIcon: const Icon(Icons.lock),
                        ),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
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
                      const SizedBox(height: 12),
                      Text(
                        widget.english
                            ? 'Signal-only mode. No exchange orders are sent.'
                            : 'حالت فقط سیگنال؛ هیچ سفارشی به صرافی ارسال نمی‌شود.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
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
  final scanner = ScannerService(TabdealApi());
  final ai = AiAnalystService();
  final history = <MarketSignal>[];
  bool loading = false;
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

  Future<void> scan() async {
    if (loading) return;
    setState(() {
      loading = true;
      status = null;
    });
    try {
      final result = await scanner.scanAll(
        timeframe: duration,
        maxConcurrency: 4,
      );
      if (!mounted) return;
      setState(() {
        signals = result;
        marketCount = result.map((e) => e.symbol).toSet().length;
        loading = false;
        status = result.isEmpty
            ? (widget.english
                ? 'No confirmed setup found.'
                : 'سیگنال تأییدشده‌ای پیدا نشد.')
            : (widget.english
                ? '${result.length} confirmed opportunities found.'
                : '${result.length} فرصت تأییدشده پیدا شد.');
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
        status = widget.english
            ? 'Market data unavailable. Check internet and retry.'
            : 'داده بازار در دسترس نیست؛ اینترنت را بررسی و دوباره تلاش کنید.';
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
      if (widget.aiUsername == null || widget.aiPassword == null) {
        throw StateError(widget.english
            ? 'Please sign in again to use AI analysis.'
            : 'برای تحلیل هوش مصنوعی دوباره وارد شوید.');
      }
      final result = await ai.analyze(
        signal: signal,
        username: widget.aiUsername!,
        password: widget.aiPassword!,
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
          title: Text(en
              ? 'Crypto Signal Scanner'
              : 'اسکنر حرفه‌ای سیگنال کریپتو'),
          actions: [
            IconButton(
              onPressed: widget.onTheme,
              tooltip: en ? 'Theme' : 'پوسته',
              icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              onPressed: widget.onLang,
              tooltip: en ? 'فارسی' : 'English',
              icon: const Icon(Icons.language),
            ),
            IconButton(
              onPressed: widget.onLogout,
              tooltip: en ? 'Logout' : 'خروج',
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
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        en
                            ? 'Full USDT market scanner'
                            : 'اسکن کامل بازارهای USDT',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(en
                          ? 'Scans public Tabdeal market data and ranks confirmed setups.'
                          : 'داده عمومی بازار تبدیل را اسکن و فرصت‌های تأییدشده را رتبه‌بندی می‌کند.'),
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
                                        value: x,
                                        child: Text(x),
                                      ))
                                  .toList(),
                              onChanged: loading
                                  ? null
                                  : (v) => setState(
                                      () => timeframe = v ?? timeframe),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: loading ? null : scan,
                              icon: const Icon(Icons.radar),
                              label: Text(loading
                                  ? (en ? 'Scanning...' : 'در حال اسکن...')
                                  : (en ? 'Scan all USDT' : 'اسکن همه USDT')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (status != null)
                Card(
                  child: ListTile(
                    leading: Icon(signals.isEmpty
                        ? Icons.info_outline
                        : Icons.check_circle_outline),
                    title: Text(status!),
                    subtitle: Text(en
                        ? 'Markets with no valid setup are filtered out.'
                        : 'بازارهای بدون شرایط معتبر فیلتر می‌شوند.'),
                  ),
                ),
              if (signals.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    en ? 'Best opportunities' : 'بهترین فرصت‌ها',
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
                        onAi: ai.configured ? () => analyzeWithAi(signal) : null,
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
              if (!ai.configured)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.psychology_outlined),
                    title: Text(en
                        ? 'AI Analyst is ready but not configured in this APK.'
                        : 'تحلیل‌گر هوش مصنوعی آماده است اما در این APK پیکربندی نشده است.'),
                    subtitle: Text(en
                        ? 'The private backend must be supplied at build time. No AI key is stored in the app.'
                        : 'بک‌اند خصوصی باید هنگام Build معرفی شود؛ هیچ کلید هوش مصنوعی داخل APK ذخیره نمی‌شود.'),
                  ),
                ),
              if (history.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    title: Text(en
                        ? 'Recent signal history (${history.length})'
                        : 'تاریخچه اخیر سیگنال‌ها (${history.length})'),
                    children: history
                        .take(20)
                        .map(
                          (s) => ListTile(
                            title: Text('${s.symbol} • ${s.side}'),
                            subtitle: Text(
                                '${money(s.entry)} → TP1 ${money(s.tp1)} • ${s.confidence.toStringAsFixed(0)}%'),
                          ),
                        )
                        .toList(),
                  ),
                ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(en ? 'Signal-only mode' : 'حالت فقط سیگنال'),
                  subtitle: Text(en
                      ? 'AI only analyzes and suggests. The app never submits orders.'
                      : 'هوش مصنوعی فقط تحلیل و پیشنهاد می‌دهد؛ برنامه هیچ سفارشی ارسال نمی‌کند.'),
                ),
              ),
              if (marketCount > 0)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    en
                        ? 'Markets with confirmed signals: $marketCount'
                        : 'بازارهای دارای سیگنال تأییدشده: $marketCount',
                    textAlign: TextAlign.center,
                  ),
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
  const _SignalCard({
    required this.signal,
    required this.en,
    required this.money,
    required this.onAi,
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
              _row('TP3', money(signal.tp3)),
              _row('ATR', money(signal.atr)),
              _row(en ? 'Risk / Reward' : 'ریسک / سود',
                  '1 : ${signal.riskReward.toStringAsFixed(1)}'),
              if (onAi != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onAi,
                    icon: const Icon(Icons.psychology_outlined),
                    label: Text(en
                        ? 'AI market analysis'
                        : 'تحلیل هوش مصنوعی بازار'),
                  ),
                ),
              ],
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
          title: Text(en ? 'AI is analyzing...' : 'هوش مصنوعی در حال تحلیل است...'),
          subtitle: Text(en
              ? 'The AI receives computed market data only; no order is sent.'
              : 'هوش مصنوعی فقط داده محاسبه‌شده بازار را دریافت می‌کند و هیچ سفارشی ارسال نمی‌شود.'),
        ),
      );
    }
    if (error != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(en ? 'AI analysis unavailable' : 'تحلیل هوش مصنوعی در دسترس نیست'),
          subtitle: Text(error!),
        ),
      );
    }
    final result = analysis;
    if (result == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  en ? 'AI Market Analyst' : 'تحلیل‌گر هوش مصنوعی بازار',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Chip(label: Text('${result.confidence}%')),
              ],
            ),
            if (signal != null) Text('${signal!.symbol} • ${signal!.side}'),
            const SizedBox(height: 10),
            Text(result.summary),
            const Divider(),
            _line(en ? 'Recommendation' : 'پیشنهاد', result.recommendation),
            _line(en ? 'Trend' : 'روند', result.trend),
            _line(en ? 'Momentum' : 'مومنتوم', result.momentum),
            _line(en ? 'Risk' : 'ریسک', result.riskLevel),
            _line(en ? 'Signal quality' : 'کیفیت سیگنال', result.signalQuality),
            if (result.bullCase.isNotEmpty)
              _line(en ? 'Bull case' : 'سناریوی صعودی', result.bullCase),
            if (result.bearCase.isNotEmpty)
              _line(en ? 'Bear case' : 'سناریوی نزولی', result.bearCase),
            if (result.invalidation.isNotEmpty)
              _line(en ? 'Invalidation' : 'شرط بی‌اعتباری', result.invalidation),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(en ? 'Reasons' : 'دلایل',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ...result.reasons.map((reason) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $reason'),
                  )),
            ],
            const SizedBox(height: 10),
            Text(
              en
                  ? 'AI confidence is analytical confidence, not a profit probability. You decide and execute manually.'
                  : 'درصد اطمینان AI اطمینان تحلیلی است، نه احتمال سود. تصمیم و اجرای معامله کاملاً دستی است.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(value),
          ],
        ),
      );
}
