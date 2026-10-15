import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/student_store.dart';
import 'domain/risk_engine.dart';
import 'ui/design.dart';
import 'ui/home.dart';
import 'ui/profile_page.dart';
import 'ui/splash_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ElThanawiyaLaunch());
}

class AppSession {
  final RiskEngine engine;
  final StudentStore store;
  const AppSession(this.engine, this.store);
}

class ElThanawiyaLaunch extends StatefulWidget {
  const ElThanawiyaLaunch({super.key});
  @override
  State<ElThanawiyaLaunch> createState() => _ElThanawiyaLaunchState();
}

class _ElThanawiyaLaunchState extends State<ElThanawiyaLaunch> {
  late Future<AppSession> session;
  bool dark = false;
  @override
  void initState() {
    super.initState();
    session = _initialize();
  }

  Future<AppSession> _initialize() async {
    final presentation = Future<void>.delayed(
      const Duration(milliseconds: 1100),
    );
    const demo = bool.fromEnvironment('DEMO');
    final store = demo
        ? StudentStore.memory(
            demo: true,
            courses:
                (jsonDecode(
                          await rootBundle.loadString(
                            'assets/demo_student.json',
                          ),
                        )['courses']
                        as List)
                    .map((course) => Map<String, dynamic>.from(course as Map))
                    .toList(),
          )
        : await StudentStore.open();
    if (mounted) setState(() => dark = store.darkMode);
    final engine = RiskEngine.fromJson(
      jsonDecode(await rootBundle.loadString('assets/course_risk.json')),
    );
    await presentation;
    return AppSession(engine, store);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppSession>(
    future: session,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ElThanawiyaApp(
          engine: snapshot.data!.engine,
          store: snapshot.data!.store,
        );
      }
      return MaterialApp(
        title: 'El-Thanawiya',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        darkTheme: appTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => systemAppearance(context, child!),
        home: snapshot.hasError
            ? Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BrandWordmark(),
                          const SizedBox(height: 28),
                          const Text(
                            'Could not open your saved data. Please try again.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          SoftButton(
                            onPressed: () =>
                                setState(() => session = _initialize()),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : const SplashPage(),
      );
    },
  );
}

Widget systemAppearance(BuildContext context, Widget child) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Palette.of(context).canvas,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    ),
    child: child,
  );
}

class ElThanawiyaApp extends StatelessWidget {
  final RiskEngine engine;
  final StudentStore store;
  const ElThanawiyaApp({super.key, required this.engine, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: 'El-Thanawiya',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      darkTheme: appTheme(dark: true),
      themeMode: store.darkMode ? ThemeMode.dark : ThemeMode.light,
      themeAnimationDuration: const Duration(milliseconds: 260),
      builder: (context, child) => systemAppearance(context, child!),
      home: store.profile == null
          ? ProfilePage(store: store)
          : HomePage(engine: engine, store: store),
    ),
  );
}
