import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/theme/motion.dart';

/// A calm card over the page while a document opens or the page is being
/// analysed (OCR, field detection). It fades in and out.
class EditorLoadingOverlay extends StatelessWidget {
  final bool loading;
  final bool detecting;
  final String? detectingLabel;

  const EditorLoadingOverlay({
    super.key,
    required this.loading,
    required this.detecting,
    this.detectingLabel,
  });

  @override
  Widget build(BuildContext context) {
    final active = loading || detecting;
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = detecting
        ? (detectingLabel ?? l10n?.analyzingDocument ?? 'Analysing the page…')
        : (l10n?.openingDocument ?? 'Opening the document…');
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: Motion.of(context, Motion.medium),
          curve: Motion.enter,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.35),
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: label,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x331B2130), blurRadius: 24, offset: Offset(0, 8))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
                      ),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
