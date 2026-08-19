import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class AppImageCache {
  const AppImageCache._();

  static const Duration _stalePeriod = Duration(days: 7);

  static const int _maxObjects = 200;

  static final CacheManager manager = CacheManager(
    Config(
      'syncmImages',
      stalePeriod: _stalePeriod,
      maxNrOfCacheObjects: _maxObjects,
    ),
  );

  static void configure() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = 40 << 20;
    cache.maximumSize = 200;
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

  static const List<int> _buckets = [128, 256, 512];

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final pixelWidth = (width * ratio).round();
    final pixelHeight = (height * ratio).round();

    final fallback = placeholder ?? const SizedBox.shrink();

    final bucket = _buckets.firstWhere(
      (size) => pixelWidth <= size,
      orElse: () => -1,
    );

    final full = bucket == -1;

    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: full ? url : '$url|$bucket',
      cacheManager: AppImageCache.manager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: pixelWidth,
      memCacheHeight: pixelHeight,
      maxWidthDiskCache: full ? null : bucket,
      maxHeightDiskCache: full ? null : bucket,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}