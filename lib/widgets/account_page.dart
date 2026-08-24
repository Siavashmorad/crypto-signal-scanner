import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_trade_store.dart';

/// SignalYab LOCAL ACCOUNT — not Tabdeal, not server authentication.
class AccountPage extends StatefulWidget {
  final bool english;
  final String currentUsername;
  final VoidCallback onLogout;

  const AccountPage({
    super.key,
    required this.english,
    required this.currentUsername,
    required this.onLogout,
  });

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool emergencyStop = false;
  bool autoTransfer = false;
  bool preferFutures = false;
  bool hasKeys = false;
  String username = '';
  final store = LocalTradeStore();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    username = widget.currentUsername;
    _userCtrl.text = widget.currentUsername;
    _load();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    hasKeys = await store.hasKeys();
    setState(() {
      emergencyStop = p.getBool('emergency_stop') ?? false;
      autoTransfer = p.getBool('auto_transfer_futures') ?? false;
      preferFutures = p.getBool('prefer_futures_execution') ?? false;
      username = p.getString('signalyab_username') ?? widget.currentUsername;
      _userCtrl.text = username;
    });
  }

  Future<void> _setBool(String key, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, v);
    await _load();
  }

  Future<void> _saveUsername() async {
    final name = _userCtrl.text.trim();
    if (name.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('signalyab_username', name);
    setState(() => username = name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.english ? 'Username updated (local)' : 'نام کاربری به‌روز شد (محلی)'),
    ));
  }

  /// Local-only password marker — stored as non-reversible hash, never logged.
  Future<void> _savePassword() async {
    final raw = _passCtrl.text;
    if (raw.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.english ? 'Min 4 characters' : 'حداقل ۴ کاراکتر'),
      ));
      return;
    }
    // Simple local hash (not server auth). Never store plaintext.
    final hash = raw.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff).toRadixString(16);
    final p = await SharedPreferences.getInstance();
    await p.setString('signalyab_password_hash', hash);
    _passCtrl.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(widget.english ? 'Local password updated' : 'رمز محلی به‌روز شد'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(en ? 'My Account' : 'حساب من')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: emergencyStop ? Colors.red.shade50 : null,
              child: ListTile(
                title: Text(
                  en
                      ? (emergencyStop
                          ? 'EMERGENCY STOP ACTIVE'
                          : 'TRADING ENABLED')
                      : (emergencyStop
                          ? 'توقف اضطراری فعال'
                          : 'معاملات فعال'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: emergencyStop ? Colors.red.shade900 : null,
                  ),
                ),
                subtitle: Text(en
                    ? 'SignalYab LOCAL ACCOUNT — not Tabdeal, not server auth'
                    : 'حساب محلی سیگنال‌یاب — نه تبدیل، نه احراز هویت سرور'),
              ),
            ),
            const SizedBox(height: 8),
            Text(en ? 'Local username' : 'نام کاربری محلی',
                style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userCtrl,
                    decoration: InputDecoration(
                      hintText: en ? 'Username' : 'نام کاربری',
                    ),
                  ),
                ),
                TextButton(onPressed: _saveUsername, child: Text(en ? 'Save' : 'ذخیره')),
              ],
            ),
            const SizedBox(height: 8),
            Text(en ? 'Local password' : 'رمز محلی',
                style: Theme.of(context).textTheme.titleSmall),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: en ? 'New password' : 'رمز جدید',
                    ),
                  ),
                ),
                TextButton(onPressed: _savePassword, child: Text(en ? 'Save' : 'ذخیره')),
              ],
            ),
            const Divider(),
            ListTile(
              title: Text(en ? 'Tabdeal API' : 'API تبدیل'),
              subtitle: Text(hasKeys
                  ? (en
                      ? 'Configured (secure storage)'
                      : 'تنظیم شده (ذخیره امن)')
                  : (en ? 'Not connected' : 'متصل نیست')),
            ),
            SwitchListTile(
              title: Text(en ? 'Emergency Stop' : 'توقف معاملات'),
              subtitle: Text(en
                  ? 'Blocks all new Spot and Futures orders'
                  : 'همه سفارش‌های جدید Spot و Futures مسدود می‌شوند'),
              value: emergencyStop,
              onChanged: (v) => _setBool('emergency_stop', v),
            ),
            SwitchListTile(
              title: Text(en ? 'Prefer Futures execution' : 'اجرای فیوچرز'),
              subtitle: Text(en
                  ? 'When ON, live opens use Futures path'
                  : 'در صورت فعال بودن، مسیر فیوچرز برای باز کردن استفاده می‌شود'),
              value: preferFutures,
              onChanged: (v) => _setBool('prefer_futures_execution', v),
            ),
            SwitchListTile(
              title: Text(en
                  ? 'Auto transfer (default OFF)'
                  : 'انتقال خودکار (پیش‌فرض خاموش)'),
              subtitle: Text(en
                  ? 'Only exact required margin when enabled'
                  : 'فقط حاشیه مورد نیاز در صورت فعال بودن'),
              value: autoTransfer,
              onChanged: (v) => _setBool('auto_transfer_futures', v),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text(en ? 'Logout' : 'خروج',
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: widget.onLogout,
            ),
          ],
        ),
      ),
    );
  }
}
