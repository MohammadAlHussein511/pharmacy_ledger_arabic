import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../security/app_lock_controller.dart';
import '../../security/pin_service.dart';
import '../widgets/pin_pad.dart';
import 'pin_entry_screen.dart'; // ← أضفنا هذا الاستيراد

/// Shown above everything while the app is locked. PIN only.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver {
  String? _message;
  bool _messageIsError = false;
  DateTime? _lockedUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshLockout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  /// Consume Android back while locked: never reveal the app behind.
  @override
  Future<bool> didPopRoute() async => true;

  Future<void> _refreshLockout() async {
    final until = await context.read<AppLockController>().pins.lockedUntil();
    if (!mounted) return;
    setState(() => _lockedUntil = until);
    _ticker?.cancel();
    if (until != null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (DateTime.now().isAfter(until)) {
          _ticker?.cancel();
          setState(() {
            _lockedUntil = null;
            _message = null;
          });
        } else {
          setState(() => _message = lockoutMessage(until));
        }
      });
    }
  }

  Future<bool> _submitPin(String pin) async {
    final lock = context.read<AppLockController>();
    final r = await lock.unlockWithPin(pin);
    if (!mounted) return true;
    if (r is PinOk) return true;
    setState(() {
      _message = pinResultMessage(r);
      _messageIsError = true;
    });
    if (r is PinLockedOut) await _refreshLockout();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: cs.primaryContainer,
                    child: Icon(Icons.menu_book_rounded, size: 36, color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(height: 14),
                Text('فتح دفتر الصيدلية',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'أدخل رمز PIN للمتابعة.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: Text(
                    _message ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _messageIsError ? cs.error : cs.onSurfaceVariant),
                  ),
                ),
                PinPad(
                  enabled: _lockedUntil == null,
                  onSubmit: _submitPin,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
