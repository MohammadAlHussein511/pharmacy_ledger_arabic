import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';  // ← أضف هذا الاستيراد في الأعلى

import 'app.dart';
import 'core/theme.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar', null);  // ← أضف هذا السطر
  // Arabic UI with Arabic digits everywhere, regardless of device locale.
  Intl.defaultLocale = 'ar';
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // [تمت الإضافة] - تهيئة الاتصال بالسحابة مع مهلة 30 ثانية وحماية من التعليق
  try {
    await Supabase.initialize(
      url: 'https://grjgjboiqvioseorymmg.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdyamdqYm9pcXZpb3Nlb3J5bW1nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE0ODQzOTYsImV4cCI6MjEwNzA2MDM5Nn0.aZTnJy-99FN-JvoU62EHdMSnBOvhxIE_gG2LQBHZgCQ',
    ).timeout(const Duration(seconds: 30));
  } catch (e) {
    runApp(_StartupErrorApp(error: e));
    return;
  }

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
                const Text('تعذّر تشغيل دفتر الصيدلية',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'بياناتك لم تتغير. أغلق التطبيق وأعد فتحه. '
                  'إذا استمرت المشكلة، أرسل رسالة الخطأ أدناه للمطوّر.',
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