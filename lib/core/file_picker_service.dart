import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

const _contentTypeByExtension = {'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png'};

class PickedFile {
  const PickedFile({required this.bytes, required this.name, required this.contentType});

  final Uint8List bytes;
  final String name;
  final String contentType;
}

/// Thin seam over `file_picker`, same shape as `SecureStore`/`CacheStore` — file_picker
/// talks to a platform channel that doesn't exist in the widget-test sandbox, so tests
/// inject a fake instead.
abstract class FilePickerService {
  Future<PickedFile?> pickDocument();
}

class RealFilePickerService implements FilePickerService {
  const RealFilePickerService();

  @override
  Future<PickedFile?> pickDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    final bytes = file.bytes;
    final contentType = _contentTypeByExtension[file.extension?.toLowerCase()];
    if (bytes == null || contentType == null) return null;
    return PickedFile(bytes: bytes, name: file.name, contentType: contentType);
  }
}
