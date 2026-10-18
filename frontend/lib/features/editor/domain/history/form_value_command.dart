import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_command.dart';

/// Sets one form field in [values] (the editor's edited values). A null
/// value removes the edit, so the field shows the file's value again.
class FormValueCommand extends EditorCommand {
  final Map<String, Object> values;
  final String field;
  final Object? before;
  final Object? after;

  FormValueCommand(this.values, this.field, {required this.before, required this.after});

  @override
  String get label => 'Fill $field';

  @override
  void execute(PageLayer layer) => _set(after);

  @override
  void undo(PageLayer layer) => _set(before);

  void _set(Object? v) {
    if (v == null) {
      values.remove(field);
    } else {
      values[field] = v;
    }
  }
}
