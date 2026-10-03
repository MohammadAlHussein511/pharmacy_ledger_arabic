import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../security/pin_service.dart';

/// Numeric keypad with PIN dots. Never displays the digits.
/// Does not require an Overlay (safe to use on the lock screen).
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmit,
    this.enabled = true,
    this.extraAction,
  });

  /// Return true to clear the entered PIN (e.g. wrong PIN).
  final Future<bool> Function(String pin) onSubmit;
  final bool enabled;

  /// Optional bottom-left key, e.g. fingerprint button.
  final Widget? extraAction;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;

  void clear() => setState(() => _pin = '');

  void _tap(String d) {
    if (!widget.enabled || _busy || _pin.length >= PinService.maxLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
  }

  void _back() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _pin.length < PinService.minLength || !widget.enabled) return;
    setState(() => _busy = true);
    final shouldClear = await widget.onSubmit(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (shouldClear) _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < (_pin.length < PinService.minLength ? PinService.minLength : _pin.length); i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? cs.primary : Colors.transparent,
                    border: Border.all(color: cs.primary, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _Key(label: d, onTap: () => _tap(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 84, height: 72, child: Center(child: widget.extraAction)),
            _Key(label: '0', onTap: () => _tap('0')),
            // [تم التعديل] - ترجمة semantics للحذف
            _Key(icon: Icons.backspace_outlined, onTap: _back, semantic: 'حذف رقم'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 252,
          child: FilledButton(
            onPressed: (_pin.length >= PinService.minLength && !_busy && widget.enabled) ? _submit : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                // [تم التعديل] - ترجمة زر المتابعة
                : const Text('متابعة'),
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, required this.onTap, this.semantic});
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final String? semantic;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        label: semantic ?? label,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 60,
              child: Center(
                child: icon != null
                    ? Icon(icon)
                    : Text(label!, style: Theme.of(context).textTheme.headlineSmall),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
