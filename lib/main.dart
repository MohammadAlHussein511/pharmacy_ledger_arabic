import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/theme.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Arabic UI with Arabic digits everywhere, regardless of device locale.
  Intl.defaultLocale = 'ar';
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    final services = await AppServices.create();
    runApp(PharmacyLedgerApp(services: services));
  } catch (e) {
    runApp(_StartupErrorApp(error: e));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 56),
                const SizedBox(height: 16),
                const Text('دفتر الصيدلية could not start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Your data has not been changed. Please close the app and open it again. '
                  'If the problem continues, restart your phone.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text('$error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

