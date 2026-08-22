import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppCacheManager extends CacheManager with ImageCacheManager {
  static const String key = 'syncmImages';

  static final AppCacheManager _instance = AppCacheManager._();
  factory AppCacheManager() => _instance;

  AppCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 200,
          ),
        );
}

class AppImageCache {
  const AppImageCache._();

  static final AppCacheManager manager = AppCacheManager();

  static void configure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = 40 << 20;
    cache.maximumSize = 200;
  }

  static CachedNetworkImageProvider provider(String url) =>
      CachedNetworkImageProvider(url, cacheManager: manager);

  static Future<void> precache(String url, BuildContext context) async {
    if (url.isEmpty) return;
    try {
      await precacheImage(provider(url), context);
    } catch (_) {
    }
  }

  static Future<void> clear() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await manager.emptyCache();
  }
}

class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
  });

  final String url;

  final double width;
  final double height;

  final BoxFit fit;
  final Widget? placeholder;

  static const List<int> _steps = [128, 192, 256, 384, 512, 768];

  static int _round(int pixels) {
    for (final step in _steps) {
      if (pixels <= step) return step;
    }
    return pixels;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final pixelWidth = _round((width * ratio).round());
    final pixelHeight = _round((height * ratio).round());

    final fallback = placeholder ?? const SizedBox.shrink();

    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: AppImageCache.manager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: pixelWidth,
      memCacheHeight: pixelHeight,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
