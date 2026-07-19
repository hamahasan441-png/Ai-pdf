import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_review_sheet.dart';
import 'package:ai_pdf/features/tools/models/filled_field.dart';

Future<List<FilledField>?> showEditorSmartFillReviewSheet(
  BuildContext context, {
  required List<FilledField> fields,
}) {
  return showModalBottomSheet<List<FilledField>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => EditorReviewSheet(fields: fields),
  );
}
