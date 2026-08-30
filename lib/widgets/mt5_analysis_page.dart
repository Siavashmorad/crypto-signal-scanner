import 'package:flutter/material.dart';

import '../services/mt5_analysis_provider.dart';
import '../services/mt5_bridge_client.dart';
import '../services/mt5_settings_store.dart';

/// MT5 read-only screen. No order, modify or close operation is exposed.
class Mt5AnalysisPage extends StatefulWidget {
  final bool english;
  const Mt5AnalysisPage({super.key, this.english = false});

  @override
  State<Mt5AnalysisPage> createState() => _Mt5AnalysisPageState();
}

class _Mt5AnalysisPageState extends State<Mt5AnalysisPage> {
  final _url = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _store = const Mt5SettingsStore();
  Mt5AnalysisProvider? _provider;
  Mt5AccountSnapshot? _account;
  List<Mt5PositionSnapshot> _positions = const [];
  bool _loading = false;
  bool _connected = false;
  String? _error;

  bool get en => widget.english;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _url.text = await _store.bridgeUrl ?? '';
    _login.text = await _store.login ?? '';
  }

  Future<void> _connect() async {
    FocusScope.of(context).unfocus();
    final baseUrl = _url.text.trim();
    final login = _login.text.trim();
    final password = _password.text;
    if (baseUrl.isEmpty || login.isEmpty || password.isEmpty) {
      setState(() => _error = en ? 'Bridge URL, Login and Password are required.' : 'آدرس پل، ورود و رمز عبور الزامی است.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _connected = false;
    });
    final provider = Mt5AnalysisProvider(
      client: Mt5BridgeClient(baseUrl: baseUrl),
    );
    try {
      if (!await provider.checkConnection()) {
        throw const Mt5BridgeException('پل MT5 آماده نیست');
      }
      await provider.login(login: login, password: password);
      final account = await provider.account();
      final positions = await provider.positions();
      await _store.save(bridgeUrl: baseUrl, login: login, password: password);
      _provider?.dispose();
      if (!mounted) return;
      setState(() {
        _provider = provider;
        _account = account;
        _positions = positions;
        _connected = true;
      });
    } catch (e) {
      provider.dispose();
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    final provider = _provider;
    if (provider == null) return _connect();
    setState(() => _loading = true);
    try {
      final account = await provider.account();
      final positions = await provider.positions();
      if (!mounted) return;
      setState(() {
        _account = account;
        _positions = positions;
        _connected = true;
        _error = null;
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

  @override
  void dispose() {
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
          title: Text(en ? 'MT5 Read-only' : 'اتصال MT5'),
          actions: [
            if (_connected)
              IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
                title: Text(_connected ? (en ? '🟢 LIVE' : '🟢 زنده') : (en ? '🔴 DISCONNECTED' : '🔴 قطع')),
                subtitle: Text(en ? 'Read-only account monitoring' : 'پایش فقط‌خواندنی حساب MT5'),
              ),
            ),
            TextField(controller: _url, decoration: InputDecoration(labelText: en ? 'Bridge URL' : 'آدرس پل MT5'), keyboardType: TextInputType.url),
            const SizedBox(height: 10),
            TextField(controller: _login, decoration: InputDecoration(labelText: en ? 'MT5 Login' : 'شماره ورود MT5'), keyboardType: TextInputType.text),
            const SizedBox(height: 10),
            TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: en ? 'MT5 Password' : 'رمز عبور MT5')),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loading ? null : _connect,
              icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link),
              label: Text(en ? 'Connect read-only' : 'اتصال فقط‌خواندنی'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(en ? 'Connection error' : 'خطای اتصال'), subtitle: Text(_error!))),
            ],
            if (_account != null) ...[
              const SizedBox(height: 14),
              Card(child: ListTile(title: Text(en ? 'Balance' : 'موجودی'), trailing: Text(_account!.balance.toStringAsFixed(2)))),
              Card(child: ListTile(title: Text(en ? 'Equity' : 'اکوئیتی'), trailing: Text(_account!.equity.toStringAsFixed(2)))),
              Card(child: ListTile(title: Text(en ? 'Margin' : 'مارجین'), trailing: Text(_account!.margin.toStringAsFixed(2)))),
              Card(
                child: ListTile(
                  title: Text(en ? 'Open positions' : 'پوزیشن‌های باز'),
                  subtitle: Text('${_positions.length}'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              color: Colors.blue.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(en
                    ? 'MT5 is read-only here: no order, modify or close operation is available. Tabdeal remains the existing execution path.'
                    : 'اتصال MT5 در این نسخه فقط‌خواندنی است: ثبت، ویرایش یا بستن سفارش ندارد. مسیر اجرای موجود همچنان تبدیل است.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
