import 'package:flutter/material.dart';

import '../services/mt5_analysis_provider.dart';
import '../services/mt5_bridge_client.dart';
import '../services/mt5_metaapi_client.dart';
import '../services/mt5_settings_store.dart';

/// MT5 read-only screen. Supports MetaAPI cloud or custom bridge.
/// No order, modify or close operation is exposed.
class Mt5AnalysisPage extends StatefulWidget {
  final bool english;
  const Mt5AnalysisPage({super.key, this.english = false});

  @override
  State<Mt5AnalysisPage> createState() => _Mt5AnalysisPageState();
}

class _Mt5AnalysisPageState extends State<Mt5AnalysisPage> {
  String _mode = 'metaapi';
  final _token = TextEditingController();
  final _accountId = TextEditingController();
  final _region = TextEditingController(text: 'new-york');
  final _url = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _store = const Mt5SettingsStore();
  Mt5AnalysisProvider? _provider;
  Mt5AccountSnapshot? _account;
  List<Mt5PositionSnapshot> _positions = const [];
  bool _loading = false;
  bool _connected = false;
  bool _hasSavedSettings = false;
  String? _message;
  String? _error;
  String _source = '';
  DateTime? _lastUpdate;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await _store.mode;
    _mode = mode;
    _url.text = await _store.bridgeUrl ?? '';
    _login.text = await _store.login ?? '';
    _password.text = await _store.password ?? '';
    _token.text = await _store.metaApiToken ?? '';
    _accountId.text = await _store.metaApiAccountId ?? '';
    _region.text = await _store.metaApiRegion;
    final saved = _mode == 'metaapi'
        ? _token.text.trim().isNotEmpty && _accountId.text.trim().isNotEmpty
        : _url.text.trim().isNotEmpty &&
            _login.text.trim().isNotEmpty &&
            _password.text.isNotEmpty;
    if (!mounted) return;
    setState(() => _hasSavedSettings = saved);
    if (saved) {
      await _connect(silent: true);
    }
  }

  Future<void> _saveOnly() async {
    FocusScope.of(context).unfocus();
    try {
      if (_mode == 'metaapi') {
        final token = _token.text.trim();
        final accountId = _accountId.text.trim();
        final region =
            _region.text.trim().isEmpty ? 'new-york' : _region.text.trim();
        if (token.isEmpty || accountId.isEmpty) {
          throw Exception(en
              ? 'MetaAPI token and Account ID are required to save.'
              : 'برای ذخیره، توکن MetaAPI و شناسه حساب الزامی است.');
        }
        await _store.saveMetaApi(
          token: token,
          accountId: accountId,
          region: region,
        );
      } else {
        final baseUrl = _url.text.trim();
        final login = _login.text.trim();
        final password = _password.text;
        if (baseUrl.isEmpty || login.isEmpty || password.isEmpty) {
          throw Exception(en
              ? 'Bridge URL, Login and Password are required to save.'
              : 'برای ذخیره، آدرس پل، ورود و رمز الزامی است.');
        }
        await _store.saveBridge(
          bridgeUrl: baseUrl,
          login: login,
          password: password,
        );
      }
      if (!mounted) return;
      setState(() {
        _hasSavedSettings = true;
        _message = en
            ? 'Saved on this phone (secure storage)'
            : 'روی این گوشی ذخیره شد (حافظه امن)';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  Future<void> _connect({bool silent = false}) async {
    FocusScope.of(context).unfocus();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _message = null;
        _connected = false;
      });
    }
    try {
      if (_mode == 'metaapi') {
        await _connectMetaApi();
      } else {
        await _connectBridge();
      }
      if (!mounted) return;
      setState(() {
        _message = en ? 'Connected (read-only)' : 'متصل شد (فقط‌خواندنی)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      if (!silent) _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectMetaApi() async {
    final token = _token.text.trim();
    final accountId = _accountId.text.trim();
    final region =
        _region.text.trim().isEmpty ? 'new-york' : _region.text.trim();
    if (token.isEmpty || accountId.isEmpty) {
      throw Exception(en
          ? 'MetaAPI token and Account ID are required.'
          : 'توکن MetaAPI و شناسه حساب الزامی است.');
    }
    final client = Mt5MetaApiClient(
      authToken: token,
      accountId: accountId,
      region: region,
    );
    final provider = Mt5AnalysisProvider.metaApi(client: client);
    try {
      if (!await provider.checkConnection()) {
        throw const Mt5BridgeException('MetaAPI پاسخ نداد');
      }
      final account = await provider.account();
      final positions = await provider.positions();
      await _store.saveMetaApi(
        token: token,
        accountId: accountId,
        region: region,
      );
      _provider?.dispose();
      if (!mounted) return;
      setState(() {
        _provider = provider;
        _account = account;
        _positions = positions;
        _connected = true;
        _hasSavedSettings = true;
        _source = 'MetaAPI ($region)';
        _lastUpdate = DateTime.now();
      });
    } catch (e) {
      provider.dispose();
      rethrow;
    }
  }

  Future<void> _connectBridge() async {
    final baseUrl = _url.text.trim();
    final login = _login.text.trim();
    final password = _password.text;
    if (baseUrl.isEmpty || login.isEmpty || password.isEmpty) {
      throw Exception(en
          ? 'Bridge URL, Login and Password are required.'
          : 'آدرس پل، ورود و رمز عبور الزامی است.');
    }
    final provider = Mt5AnalysisProvider.bridge(
      client: Mt5BridgeClient(baseUrl: baseUrl),
    );
    try {
      if (!await provider.checkConnection()) {
        throw const Mt5BridgeException('پل MT5 آماده نیست');
      }
      await provider.login(login: login, password: password);
      final account = await provider.account();
      final positions = await provider.positions();
      await _store.saveBridge(
        bridgeUrl: baseUrl,
        login: login,
        password: password,
      );
      _provider?.dispose();
      if (!mounted) return;
      setState(() {
        _provider = provider;
        _account = account;
        _positions = positions;
        _connected = true;
        _hasSavedSettings = true;
        _source = 'Bridge';
        _lastUpdate = DateTime.now();
      });
    } catch (e) {
      provider.dispose();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final provider = _provider;
    if (provider == null) return _connect();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final account = await provider.account();
      final positions = await provider.positions();
      if (!mounted) return;
      setState(() {
        _account = account;
        _positions = positions;
        _connected = true;
        _lastUpdate = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearSaved() async {
    await _store.clear();
    _provider?.dispose();
    _provider = null;
    if (!mounted) return;
    setState(() {
      _token.clear();
      _accountId.clear();
      _region.text = 'new-york';
      _url.clear();
      _login.clear();
      _password.clear();
      _account = null;
      _positions = const [];
      _connected = false;
      _hasSavedSettings = false;
      _source = '';
      _lastUpdate = null;
      _error = null;
      _message = en ? 'Cleared' : 'پاک شد';
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
  }

  @override
  void dispose() {
    _token.dispose();
    _accountId.dispose();
    _region.dispose();
    _url.dispose();
    _login.dispose();
    _password.dispose();
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(en ? 'MT5 connection' : 'اتصال MT5'),
          actions: [
            if (_connected)
              IconButton(
                onPressed: _loading ? null : _refresh,
                tooltip: en ? 'Refresh' : 'به‌روزرسانی',
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
                title: Text(
                  _connected
                      ? (en ? '🟢 LIVE' : '🟢 زنده')
                      : (en ? '🔴 DISCONNECTED' : '🔴 قطع'),
                ),
                subtitle: Text(
                  _connected
                      ? (en
                          ? 'Read-only · $_source'
                          : 'فقط‌خواندنی · $_source')
                      : (en
                          ? 'Enter credentials below (like Tabdeal API settings)'
                          : 'اطلاعات را مثل API تبدیل اینجا وارد کنید'),
                ),
              ),
            ),
            if (_lastUpdate != null) ...[
              const SizedBox(height: 4),
              Text(
                en
                    ? 'Last update: ${_lastUpdate!.toLocal()}'
                    : 'آخرین به‌روزرسانی: ${_lastUpdate!.toLocal()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'metaapi',
                  label: const Text('MetaAPI'),
                  icon: const Icon(Icons.cloud),
                ),
                ButtonSegment(
                  value: 'bridge',
                  label: Text(en ? 'Custom bridge' : 'پل اختصاصی'),
                  icon: const Icon(Icons.dns),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() {
                  _mode = s.first;
                  _error = null;
                  _connected = false;
                });
              },
            ),
            const SizedBox(height: 12),
            if (_mode == 'metaapi') ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    en
                        ? '1) Create account on metaapi.cloud\n2) Add MT5 (prefer Investor password)\n3) Copy Token + Account ID + Region\n4) Save here, then Test connection\nCredentials stay only on this phone.'
                        : '۱) در metaapi.cloud حساب بسازید\n۲) حساب MT5 را اضافه کنید (ترجیحاً رمز Investor)\n۳) Token و Account ID و Region را کپی کنید\n۴) اینجا ذخیره کنید، بعد تست اتصال بزنید\nاطلاعات فقط روی همین گوشی می‌ماند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: en ? 'MetaAPI token' : 'توکن MetaAPI',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _accountId,
                decoration: InputDecoration(
                  labelText: en ? 'Account ID (UUID)' : 'شناسه حساب (UUID)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _region,
                decoration: InputDecoration(
                  labelText: en
                      ? 'Region (new-york, london, …)'
                      : 'منطقه (new-york، london، …)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.public),
                ),
              ),
            ] else ...[
              TextField(
                controller: _url,
                decoration: InputDecoration(
                  labelText: en ? 'Bridge URL' : 'آدرس پل MT5',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _login,
                decoration: InputDecoration(
                  labelText: en ? 'MT5 Login' : 'شماره ورود MT5',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: en ? 'MT5 Password' : 'رمز عبور MT5',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_message!),
              ),
            FilledButton.icon(
              onPressed: _loading ? null : _saveOnly,
              icon: const Icon(Icons.save),
              label: Text(en ? 'Save on this phone' : 'ذخیره روی این گوشی'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _connect(),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_user),
              label: Text(en ? 'Test / Connect read-only' : 'تست / اتصال فقط‌خواندنی'),
            ),
            if (_hasSavedSettings) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loading ? null : _clearSaved,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                    en ? 'Clear saved connection' : 'پاک کردن اطلاعات اتصال'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(en ? 'Connection error' : 'خطای اتصال'),
                  subtitle: Text(_error!),
                ),
              ),
            ],
            if (_account != null) ...[
              const SizedBox(height: 14),
              Card(
                child: ListTile(
                  title: Text(en ? 'Balance' : 'موجودی'),
                  trailing: Text(_account!.balance.toStringAsFixed(2)),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(en ? 'Equity' : 'اکوئیتی'),
                  trailing: Text(_account!.equity.toStringAsFixed(2)),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(en ? 'Margin' : 'مارجین'),
                  trailing: Text(_account!.margin.toStringAsFixed(2)),
                ),
              ),
              Card(
                child: ListTile(
                  title: Text(en ? 'Open positions' : 'پوزیشن‌های باز'),
                  subtitle: Text('${_positions.length}'),
                ),
              ),
              ..._positions.take(20).map(
                    (p) => Card(
                      child: ListTile(
                        title: Text('${p.symbol} ${p.side}'),
                        subtitle: Text(
                          en
                              ? 'Vol ${p.volume} · Open ${p.openPrice}'
                              : 'حجم ${p.volume} · ورود ${p.openPrice}',
                        ),
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 12),
            Card(
              color: Colors.blue.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  en
                      ? 'MT5 is read-only: no order, modify or close. Tabdeal remains the execution path.'
                      : 'MT5 فقط‌خواندنی است: ثبت/ویرایش/بستن سفارش ندارد. مسیر اجرا همچنان تبدیل است.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
