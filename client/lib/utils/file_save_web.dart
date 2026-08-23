// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Future<String?> saveBytesToFile(String fileName, Uint8List bytes) async {
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);

  try {
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    return fileName;
  } finally {
    // Ссылка держит блоб в памяти, пока её не отозвать.
    html.Url.revokeObjectUrl(url);
  }
}
