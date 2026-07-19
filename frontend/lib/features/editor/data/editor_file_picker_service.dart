import 'package:file_picker/file_picker.dart';

class EditorPickedFile {
  final String path;
  final String name;

  const EditorPickedFile({required this.path, required this.name});
}

/// Wraps the platform file picker for editor-supported document/image types.
class EditorFilePickerService {
  const EditorFilePickerService();

  Future<EditorPickedFile?> pickSupportedFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null) return null;
    return EditorPickedFile(path: path, name: result.files.first.name);
  }
}
