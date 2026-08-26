import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String?> saveBytesToFile(String fileName, Uint8List bytes) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);

  try {
    web.HTMLAnchorElement()
      ..href = url
      ..setAttribute('download', fileName)
      ..click();
    return fileName;
  } finally {
    // Ссылка держит блоб в памяти, пока её не отозвать.
    web.URL.revokeObjectURL(url);
  }
}
