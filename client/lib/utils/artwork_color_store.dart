import 'dart:async';
import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:palette_generator/palette_generator.dart';

import 'image_cache.dart';
import 'local_store.dart';

class ArtworkColorStore {
  const ArtworkColorStore._();

  /// Цвета в памяти. Порядок вставки = порядок вытеснения.
  static final Map<String, Color> _colors = {};

  static final Map<String, Future<Color?>> _pending = {};

  static bool _restored = false;
  static Timer? _saveTimer;

  static const int _limit = 200;

  static const Duration _saveDelay = Duration(seconds: 2);

  static void restore() {
    if (_restored) return;
    _restored = true;

    final saved = LocalStore.readMap(StoreKeys.artworkColors);
    if (saved == null) return;

    for (final entry in saved.entries) {
      final value = entry.value;
      if (value is int) _colors[entry.key] = Color(value);
    }
  }

  static Color? cached(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!_restored) restore();
    return _colors[url];
  }

  static void remember(String url, Color color) {
    if (url.isEmpty) return;
    if (!_restored) restore();
    if (_colors[url] == color) return;

    if (!_colors.containsKey(url) && _colors.length >= _limit) {
      _colors.remove(_colors.keys.first);
    }
    _colors[url] = color;
    _scheduleSave();
  }

  static Future<Color?> resolve(String url) {
    if (url.isEmpty) return Future<Color?>.value();
    if (!_restored) restore();

    final ready = _colors[url];
    if (ready != null) return Future<Color?>.value(ready);

    final running = _pending[url];
    if (running != null) return running;

    final future = _compute(url);
    _pending[url] = future;
    return future;
  }

  static void warmUp(Iterable<String> urls) {
    if (!_restored) restore();

    for (final url in urls) {
      if (url.isEmpty || _colors.containsKey(url) || _pending.containsKey(url)) {
        continue;
      }

      SchedulerBinding.instance.scheduleTask<void>(
        () {
          if (_colors.containsKey(url) || _pending.containsKey(url)) return;
          resolve(url).ignore();
        },
        Priority.idle,
      );
    }
  }

  static Future<Color?> _compute(String url) async {
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        AppImageCache.provider(url),
        size: const Size(48, 48),
        maximumColorCount: 8,
      );

      final color = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color;

      if (color != null) remember(url, color);
      return color;
    } catch (err) {
      debugPrint('Не удалось снять цвет с картинки: $err');
      return null;
    } finally {
      _pending.remove(url)?.ignore();
    }
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _save);
  }

  static void _save() {
    _saveTimer = null;
    final snapshot = <String, dynamic>{
      for (final entry in _colors.entries) entry.key: entry.value.toARGB32(),
    };
    unawaited(LocalStore.saveMap(StoreKeys.artworkColors, snapshot));
  }

  @visibleForTesting
  static void resetForTest() {
    _colors.clear();
    _pending.clear();
    _saveTimer?.cancel();
    _saveTimer = null;
    _restored = false;
  }
}
