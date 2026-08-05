import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class TappableAvatar extends StatelessWidget {
  const TappableAvatar({
    super.key,
    required this.imageUrl,
    required this.radius,
    this.heroTag,
    this.fallbackIcon = Icons.person_rounded,
    this.showRing = false,
    this.title,
  });

  final String? imageUrl;
  final double radius;

  final Object? heroTag;

  final IconData fallbackIcon;
  final bool showRing;

  final String? title;

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  static String _initialsOf(String? name) {
    final text = (name ?? '').trim();
    if (text.isEmpty) return '';

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    if (words.length == 1) return words.first.characters.first.toUpperCase();

    return (words[0].characters.first + words[1].characters.first).toUpperCase();
  }

  static Color _colorFor(String? name, ColorScheme colors) {
    final palette = [
      colors.primaryContainer,
      colors.secondaryContainer,
      colors.tertiaryContainer,
    ];
    final text = name ?? '';
    if (text.isEmpty) return palette.first;

    var sum = 0;
    for (final unit in text.codeUnits) {
      sum = (sum + unit) % 1000;
    }
    return palette[sum % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tag = heroTag ?? imageUrl ?? 'avatar';

    final initials = _initialsOf(title);
    final tint = initials.isEmpty ? colors.primaryContainer : _colorFor(title, colors);

    final placeholder = Container(
      width: radius * 2,
      height: radius * 2,
      color: tint,
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(fallbackIcon, size: radius, color: colors.onPrimaryContainer)
          : Text(
              initials,
              style: TextStyle(
                fontSize: radius * 0.8,
                fontWeight: FontWeight.w700,
                color: colors.onPrimaryContainer,
              ),
            ),
    );

    Widget avatar = ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: _hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              )
            : placeholder,
      ),
    );

    if (showRing) {
      avatar = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.primary.withValues(alpha: 0.35), width: 2),
        ),
        child: avatar,
      );
    }

    if (!_hasImage) return avatar;

    return GestureDetector(
      onTap: () => _open(context, tag),
      child: Hero(
        tag: tag,
        flightShuttleBuilder: (context, animation, direction, from, to) {
          return _FlightImage(imageUrl: imageUrl!, animation: animation);
        },
        child: avatar,
      ),
    );
  }

  void _open(BuildContext context, Object tag) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.86),
        transitionDuration: AppMotion.medium,
        reverseTransitionDuration: AppMotion.short,
        pageBuilder: (_, animation, __) => _AvatarViewer(
          imageUrl: imageUrl!,
          heroTag: tag,
          title: title,
          animation: animation,
        ),
      ),
    );
  }
}

class _FlightImage extends StatelessWidget {
  const _FlightImage({required this.imageUrl, required this.animation});

  final String imageUrl;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(animation.value);
        return ClipRRect(
          borderRadius: BorderRadius.circular(1000 * (1 - t) + AppRadius.lg * t),
          child: CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover),
        );
      },
    );
  }
}

class _AvatarViewer extends StatefulWidget {
  const _AvatarViewer({
    required this.imageUrl,
    required this.heroTag,
    required this.animation,
    this.title,
  });

  final String imageUrl;
  final Object heroTag;
  final String? title;
  final Animation<double> animation;

  @override
  State<_AvatarViewer> createState() => _AvatarViewerState();
}

class _AvatarViewerState extends State<_AvatarViewer> {
  double _dragOffset = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_dragOffset > 120 || velocity > 700) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    // Чем дальше утянули вниз, тем прозрачнее фон — видно, что жест работает.
    final dragProgress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 1 - dragProgress,
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: Hero(
                      tag: widget.heroTag,
                      child: GestureDetector(
                        onTap: () {},
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: ClipRRect(
                            borderRadius: AppRadius.large,
                            child: CachedNetworkImage(
                              imageUrl: widget.imageUrl,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const SizedBox(
                                width: 64,
                                height: 64,
                                child: Center(child: CircularProgressIndicator()),
                              ),
                              errorWidget: (_, __, ___) => const Icon(
                                Icons.broken_image_rounded,
                                size: 64,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.title != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Opacity(
                    opacity: 1 - dragProgress,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        widget.title!,
                        textAlign: TextAlign.center,
                        style: texts.titleMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white,
                  tooltip: 'Закрыть',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}