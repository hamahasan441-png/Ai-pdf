import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// The bar that sits on the keyboard while a form is filled: previous and
/// next field, the field's name, a calendar for date fields, Reset (clears
/// this field) and Done.
class FormFillBar extends StatelessWidget {
  final String label;
  final bool required;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPickDate;
  final VoidCallback onReset;
  final VoidCallback onDone;

  const FormFillBar({
    super.key,
    required this.label,
    this.required = false,
    this.onPrevious,
    this.onNext,
    this.onPickDate,
    required this.onReset,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    Widget arrow(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          icon: Icon(icon, size: 26),
          style: IconButton.styleFrom(
            side: BorderSide(color: onTap == null ? cs.outlineVariant : cs.outline),
            shape: const CircleBorder(),
          ),
        );
    return Material(
      color: cs.surface,
      elevation: 8,
      shadowColor: const Color(0x331B2130),
      child: SafeArea(
        top: false,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Row(
            children: [
              arrow(Icons.arrow_back, l10n?.formPreviousField ?? 'Previous field', onPrevious),
              const SizedBox(width: 4),
              arrow(Icons.arrow_forward, l10n?.formNextField ?? 'Next field', onNext),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label),
                    if (required) const TextSpan(text: ' *', style: TextStyle(color: Color(0xFFD32F2F))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
              if (onPickDate != null)
                IconButton(
                  tooltip: l10n?.fieldKindDate ?? 'Date',
                  onPressed: onPickDate,
                  icon: Icon(Icons.event_outlined, color: cs.primary),
                ),
              TextButton(onPressed: onReset, child: Text(l10n?.formReset ?? 'Reset')),
              TextButton(
                onPressed: onDone,
                style: TextButton.styleFrom(textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                child: Text(l10n?.done ?? 'Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
