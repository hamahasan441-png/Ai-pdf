import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';

/// The name of a scan filter in the user's language.
String scanFilterLabel(AppLocalizations l10n, ScanFilter filter) => switch (filter) {
      ScanFilter.original => l10n.scanFilterOriginal,
      ScanFilter.auto => l10n.scanFilterAuto,
      ScanFilter.grayscale => l10n.scanFilterGrayscale,
      ScanFilter.blackWhite => l10n.scanFilterBlackWhite,
      ScanFilter.photo => l10n.scanFilterPhoto,
    };
