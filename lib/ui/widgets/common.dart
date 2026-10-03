import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/currency.dart';
import '../../core/money.dart';
import '../../domain/period_summary.dart';

class AmountText extends StatelessWidget {
  const AmountText(this.minor, this.currency, {super.key, this.style, this.muted = false});
  final int minor;
  final Currency currency;
  final TextStyle? style;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium!;
    return Text(
      Money.format(minor, currency),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w600,
        color: muted ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6) : null,
      ),
    );
  }
}

/// A label/amount line that never overlaps: the amount scales down on
/// narrow screens instead of overflowing.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.minor,
    required this.currency,
    this.emphasized = false,
    this.muted = false,
  });

  final String label;
  final int minor;
  final Currency currency;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: (emphasized ? t.titleSmall : t.bodyMedium)
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: AmountText(minor, currency,
                  muted: muted, style: emphasized ? t.titleLarge : t.titleMedium),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sales + per-currency payments for a period. Currencies are never combined.
class SummaryBlock extends StatelessWidget {
  const SummaryBlock({
    super.key,
    required this.summary,
    this.showAllCurrencies = false,
    // [تم التعديل] - ترجمة تسمية المبيعات الافتراضية
    this.salesLabel = 'المبيعات',
    this.emphasized = false,
  });

  final PeriodSummary summary;

  /// Dashboard style: always show TRY, USD and SYP lines (zeros muted).
  final bool showAllCurrencies;
  final String salesLabel;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final currencies = showAllCurrencies ? Currency.reportOrder : summary.paidCurrencies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AmountRow(
          label: salesLabel,
          minor: summary.salesMinor,
          currency: Currency.salesCurrency,
          emphasized: emphasized,
          muted: summary.salesMinor == 0,
        ),
        const SizedBox(height: 6),
        // [تم التعديل] - ترجمة "الدفعات"
        Text('الدفعات',
            style: t.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (currencies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            // [تم التعديل] - ترجمة "لا توجد دفعات"
            child: Text('لا توجد دفعات',
                style: t.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          for (final c in currencies)
            AmountRow(
              // [تم التعديل] - ترجمة تسمية دفعات العملة
              label: 'دفعات ${c.code}',
              minor: summary.payment(c),
              currency: c,
              muted: summary.payment(c) == 0,
            ),
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title!, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            if (subtitle != null)
                              Text(subtitle!,
                                  style: t.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (trailing != null) trailing!,
                      if (onTap != null && trailing == null)
                        Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon, this.action});
  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        children: [
          Icon(icon ?? Icons.receipt_long_outlined, size: 36, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : SingleChildScrollView(child: Text(message)),
        actions: [
          // [تم التعديل] - ترجمة زر الإلغاء
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: cs.error,
                    foregroundColor: cs.onError,
                    minimumSize: const Size(64, 40))
                : FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message)));
}

/// "< September 2026 >" style period switcher.
class PeriodSwitcher extends StatelessWidget {
  const PeriodSwitcher({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.onTapLabel,
    this.canGoNext = true,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onTapLabel;
  final bool canGoNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
            // [تم التعديل] - ترجمة tooltip السابق
            tooltip: 'السابق', onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: TextButton(
            onPressed: onTapLabel,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (onTapLabel != null) const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        IconButton.filledTonal(
            // [تم التعديل] - ترجمة tooltip التالي
            tooltip: 'التالي', onPressed: canGoNext ? onNext : null, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}
