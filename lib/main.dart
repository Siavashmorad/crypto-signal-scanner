import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/home_page.dart';

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
  Widget build(BuildContext context) {
    final en = widget.english;
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(en ? 'SignalYab' : 'سیگنال‌یاب',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    TextField(
                      controller: username,
                      decoration: InputDecoration(
                          labelText: en ? 'Username' : 'نام کاربری'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration:
                          InputDecoration(labelText: en ? 'Password' : 'رمز'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: login,
                      child: Text(en ? 'Login' : 'ورود'),
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
}
