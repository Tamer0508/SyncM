import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<String?> saveBytesToFile(String fileName, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: bytes,
  );

  if (path == null) return null;

  if (Platform.isAndroid || Platform.isIOS) return path;

  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
