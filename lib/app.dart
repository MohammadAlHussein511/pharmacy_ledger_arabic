import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme.dart';
import 'security/app_lock_controller.dart';
import 'services.dart';
import 'ui/day_clock.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/theme_controller.dart';

class PharmacyLedgerApp extends StatefulWidget {
  const PharmacyLedgerApp({super.key, required this.services});
  final AppServices services;

  @override
  State<PharmacyLedgerApp> createState() => _PharmacyLedgerAppState();
}

class _PharmacyLedgerAppState extends State<PharmacyLedgerApp> {
  late bool _onboarded = widget.services.settings.onboardingDone;
  final _dayClock = DayClock();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(widget.services.lock);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(widget.services.lock);
    _dayClock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: s),
        ChangeNotifierProvider.value(value: s.store),
        ChangeNotifierProvider.value(value: s.lock),
        ChangeNotifierProvider.value(value: s.theme),
        ChangeNotifierProvider.value(value: _dayClock),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'دفتر الصيدلية',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          // Force RTL for Arabic
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
              child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.4),
              ),
              child: _LockGate(child: child ?? const SizedBox.shrink()),
            ),
          ),
          home: _onboarded
              ? const HomeShell()
              : WelcomeScreen(onDone: () async {
                  await s.settings.setOnboardingDone();
                  setState(() => _onboarded = true);
                }
              ),
            ),
          ),
        ),
  }
}

/// Covers the whole navigator with the lock screen while locked, so no
/// financial data is visible (also in the recent-apps preview).
class _LockGate extends StatelessWidget {
  const _LockGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    return Stack(
      children: [
        Offstage(offstage: lock.locked, child: TickerMode(enabled: !lock.locked, child: child)),
        if (lock.locked)
          Positioned.fill(
            // Own navigator gives the lock screen an Overlay without
            // disturbing the user's place in the main navigation stack.
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, __, ___) => const LockScreen(),
              ),
            ),
          ),
      ],
    );
  }
}
