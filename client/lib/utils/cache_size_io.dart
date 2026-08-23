import 'dart:io';

import 'package:flutter/foundation.dart';

import 'image_cache.dart';

Future<int?> imageCacheDiskBytes() async {
  try {
    final probe = await AppImageCache.manager.store.fileSystem.createFile('.probe');
    final dir = Directory(probe.parent.path);
    if (!await dir.exists()) return 0;

    var total = 0;
    await for (final entity in dir.list(followLinks: false)) {
      final stat = await entity.stat();
      if (stat.type == FileSystemEntityType.file) total += stat.size;
    }
    return total;
  } catch (err) {
    debugPrint('Не удалось измерить дисковый кэш: $err');
    return null;
  }
}
