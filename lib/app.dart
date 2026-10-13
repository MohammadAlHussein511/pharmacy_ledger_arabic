import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

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
      child: Consumer2<ThemeController, AppLockController>(
        builder: (context, theme, lock, _) => MaterialApp(
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
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.4),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          onUnknownRoute: (_) => MaterialPageRoute<void>(
            builder: (_) => const HomeShell(),
          ),
          home: Builder(
            builder: (context) {
              if (lock.locked) {
                return const LockScreen();
              }
              if (!_onboarded) {
                return WelcomeScreen(onDone: () async {
                  await s.settings.setOnboardingDone();
                  setState(() => _onboarded = true);
                });
              }
              return const HomeShell();
            },
          ),
        ),
      ),
    );
  }
}