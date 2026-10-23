import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Says up front that this tool saves each page as a picture: the result
/// looks the same but its text can no longer be selected, searched or
/// copied, and links, form fields and bookmarks are not kept.
class RasterNotice extends StatelessWidget {
  const RasterNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 18, color: cs.onSecondaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(l10n.toolRasterNotice, style: TextStyle(fontSize: 12.5, color: cs.onSecondaryContainer, height: 1.35)),
        ),
      ]),
    );
  }
}
