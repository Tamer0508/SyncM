import 'dart:async';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/playback_provider.dart';
import '../../theme.dart';
import 'artwork_pager.dart';
import '../../utils/image_cache.dart';

class NowPlayingScreen extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? artworkUrl;

  final bool insideSheet;

  const NowPlayingScreen({
    super.key,
    this.title,
    this.artist,
    this.artworkUrl,
    this.insideSheet = false,
  });

  static Future<void> open(
    BuildContext context, {
    String? title,
    String? artist,
    String? artworkUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      constraints: const BoxConstraints.expand(),
      barrierColor: Colors.black.withValues(alpha: 0.4),
      showDragHandle: false,
      useSafeArea: false,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        child: NowPlayingScreen(
          title: title,
          artist: artist,
          artworkUrl: artworkUrl,
          insideSheet: true,
        ),
      ),
    );
  }

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  int _positionMs = 0;
  bool _dragging = false;

  int? _lastSyncPosition;

  late AnimationController _colorAnimController;
  late Animation<Color?> _colorDominantAnim;
  late Animation<Color?> _colorVibrantAnim;

  Color _displayDominant = Colors.deepPurple;
  Color _displayVibrant = Colors.purpleAccent;
  Color _targetDominant = Colors.deepPurple;
  Color _targetVibrant = Colors.purpleAccent;

  String? _lastTrackUri;
  int? _lastPaletteImageSig;

  int _paletteRequest = 0;

  bool _entered = false;

  VoidCallback? _pendingPalette;

  Animation<double>? _routeAnimation;

  late final AnimationController _entrance;

  double _dragOffset = 0;

  Animation<double> _stagger(double delay) => CurvedAnimation(
        parent: _entrance,
        curve: Interval(delay, 1, curve: AppMotion.enter),
      );

  Widget _rise({
    required Widget child,
    required double delay,
    double offset = 28,
  }) {
    if (context.reduceMotion) return child;

    final animation = _stagger(delay);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        final t = animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * offset),
            child: inner,
          ),
        );
      },
      child: child,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, _routeAnimation)) return;

    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _routeAnimation = animation;

    if (animation == null || animation.isCompleted) {
      _markEntered();
      return;
    }
    animation.addStatusListener(_onRouteAnimation);
  }

  void _onRouteAnimation(AnimationStatus status) {
    if (status == AnimationStatus.completed) _markEntered();
  }

  Map<String, dynamic>? _lastKnownTrack;

  final ValueNotifier<double> _swipeProgress = ValueNotifier(0);

  final GlobalKey<ArtworkPagerState> _pagerKey = GlobalKey();

  final Set<String> _warmedArtwork = {};

  void _warmUpcoming(List<String> urls) {
    if (!_entered) return;

    final fresh = urls.where((url) => _warmedArtwork.add(url)).toList();
    if (fresh.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in fresh) {
        precacheImage(
          CachedNetworkImageProvider(url, cacheManager: AppImageCache.manager),
          context,
          onError: (_, _) {},
        );
      }
    });
  }

  ArtworkSource? _neighbourSource(Map<String, dynamic>? track) {
    final url = track?['imageUrl'] as String?;
    if (url == null || url.isEmpty) return null;
    return ArtworkSource(url: url);
  }

  void _adoptNeighbourColor(PlaybackProvider pb, int direction) {
    final track =
        direction > 0 ? pb.nextQueueTrack : pb.previousQueueTrack;
    final color = pb.dominantColorForUrl(track?['imageUrl'] as String?);
    if (color == null) return;

    _colorAnimController.stop();
    setState(() {
      _displayDominant = color;
      _targetDominant = color;
    });
  }

  void _slideTo(int direction, VoidCallback fallback) {
    final pager = _pagerKey.currentState;
    if (pager != null && pager.animateTo(direction)) return;
    fallback();
  }

  void _markEntered() {
    if (_entered || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _entered) return;
      setState(() => _entered = true);
      final pending = _pendingPalette;
      _pendingPalette = null;
      pending?.call();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = _dragOffset + details.delta.dy;
    setState(() => _dragOffset = next < 0 ? 0 : next);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final height = MediaQuery.sizeOf(context).height;

    if (_dragOffset > height * 0.25 || velocity > 900) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _dragOffset = 0);
  }


  @override
  void initState() {
    super.initState();
    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    _positionMs = pb.positionMs;

    _entrance = AnimationController(vsync: this, duration: AppMotion.page)
      ..forward();

    _startTimer();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: AppMotion.tint,
    );
    _colorDominantAnim = ColorTween(begin: _displayDominant, end: _displayDominant)
        .animate(_colorAnimController);
    _colorVibrantAnim = ColorTween(begin: _displayVibrant, end: _displayVibrant)
        .animate(_colorAnimController);

    _colorAnimController.addListener(() {
      setState(() {
        _displayDominant = _colorDominantAnim.value!;
        _displayVibrant = _colorVibrantAnim.value!;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _swipeProgress.dispose();
    _entrance.dispose();
    _colorAnimController.dispose();
    super.dispose();
  }

  void _startTimer() {
  _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (!mounted) return;
    final pb = Provider.of<PlaybackProvider>(context, listen: false);

    if (_dragging) return;

    if (pb.sessionMode) {
      final serverPos = pb.positionMs;
      if (serverPos != _positionMs) {
        setState(() => _positionMs = serverPos);
      }
    } else if (pb.isPlaying) {
      setState(() {
        _positionMs = (_positionMs + 200).clamp(0, pb.durationMs);
      });
    }
  });
}


  int _imageSignature(Uint8List bytes, String? uri) {
    int hash = (uri?.hashCode ?? 0) ^ 0x9E3779B1;
    hash = 0x1fffffff & (hash + bytes.length);
    final int len = bytes.length;
    if (len > 0) {
      final int step = len < 64 ? 1 : len ~/ 64;
      for (int i = 0; i < len; i += step) {
        hash = 0x1fffffff & (hash + bytes[i]);
        hash = 0x1fffffff & (hash + (0x0007ffff & (hash << 10)));
        hash ^= (hash >> 6);
      }
    }
    hash = 0x1fffffff & (hash + (0x03ffffff & (hash << 3)));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + (0x00003fff & (hash << 15)));
    return hash;
  }

  void _setTargetColors(Color dominant, Color vibrant) {
    if (_targetDominant == dominant && _targetVibrant == vibrant) return;
    _targetDominant = dominant;
    _targetVibrant = vibrant;

    _colorDominantAnim = ColorTween(begin: _displayDominant, end: dominant)
        .animate(_colorAnimController);
    _colorVibrantAnim = ColorTween(begin: _displayVibrant, end: vibrant)
        .animate(_colorAnimController);

    _colorAnimController
      ..reset()
      ..forward();
  }

  Future<void> _updatePalette({
    Uint8List? imageBytes,
    String? imageUrl,
    required String? trackUri,
  }) async {
    if (imageBytes == null && (imageUrl == null || imageUrl.isEmpty)) {
      _setTargetColors(Colors.deepPurple, Colors.purpleAccent);
      return;
    }

    final provider = Provider.of<PlaybackProvider>(context, listen: false);

    final String? cacheKey = imageUrl ?? trackUri;

    if (cacheKey != null && provider.paletteCache.containsKey(cacheKey)) {
      final p = provider.paletteCache[cacheKey]!;
      _applyPalette(p, trackUri, provider);
      return;
    }

    if (!_entered) {
      _pendingPalette = () => _updatePalette(
            imageBytes: imageBytes,
            imageUrl: imageUrl,
            trackUri: trackUri,
          );
      return;
    }

    final request = ++_paletteRequest;

    try {
      final ImageProvider<Object> providerImg;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        providerImg = NetworkImage(imageUrl);
      } else {
        providerImg = MemoryImage(imageBytes!);
      }

      final palette = await PaletteGenerator.fromImageProvider(
        providerImg,
        size: const Size(64, 64),
        maximumColorCount: 8,
      );

      if (!mounted || request != _paletteRequest) return;

      if (cacheKey != null) {
        if (provider.paletteCache.length > 60) {
          provider.paletteCache.remove(provider.paletteCache.keys.first);
        }
        provider.paletteCache[cacheKey] = palette;
      }

      _applyPalette(palette, trackUri, provider);
    } catch (err) {
      debugPrint('Palette extraction failed: $err');
    }
  }

  void _applyPalette(PaletteGenerator p, String? trackUri, PlaybackProvider provider) {
    if (!mounted) return;
    final current = provider.currentTrack?['uri'];
    if (trackUri != null && current != null && current != trackUri) {
      return;
    }
    _setTargetColors(
      p.dominantColor?.color ?? Colors.deepPurple,
      p.vibrantColor?.color ?? (p.lightVibrantColor?.color ?? Colors.purpleAccent),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Consumer<PlaybackProvider>(
      builder: (ctx, pb, _) {
        final live = pb.currentTrack;
        if (live != null) _lastKnownTrack = live;
        final track = live ?? _lastKnownTrack;

        final title = track?['title'] ?? widget.title ?? 'Unknown Title';
        final artist = track?['artist'] ?? widget.artist ?? 'Unknown Artist';
        final duration = pb.durationMs;
        final imageBytes = pb.currentImageBytes;
        final imageUrl = (track?['imageUrl'] as String?) ??
            (track == null ? widget.artworkUrl : null);
        final currentUri = track?['uri'];

        _warmUpcoming(pb.neighbourArtworkUrls);

        if (!_dragging) {
          if (_lastSyncPosition != pb.positionMs) {
            _positionMs = pb.positionMs;
            _lastSyncPosition = pb.positionMs;
          }
        }

        if (currentUri != _lastTrackUri) {
          _lastTrackUri = currentUri;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final freshBytes = pb.currentImageBytes;
            final freshUrl = pb.currentTrack?['imageUrl'] ?? widget.artworkUrl;

            final cached = freshUrl != null ? pb.paletteCache[freshUrl] : null;
            if (cached != null) {
              _setTargetColors(
                cached.dominantColor?.color ?? Colors.blueGrey.shade800,
                cached.vibrantColor?.color ?? Colors.blueGrey.shade600,
              );
            } else {
              _setTargetColors(Colors.blueGrey.shade900, Colors.blueGrey.shade700);
            }

            _updatePalette(imageBytes: freshBytes, imageUrl: freshUrl, trackUri: currentUri);
          });
        }

        final imageUrlNow = pb.currentTrack?['imageUrl'] as String? ?? widget.artworkUrl;
        final int? imageSig = imageBytes != null
            ? _imageSignature(imageBytes, currentUri)
            : (imageUrlNow != null ? Object.hash(imageUrlNow, currentUri) : null);

        if (imageSig != null && imageSig != _lastPaletteImageSig) {
          _lastPaletteImageSig = imageSig;
          final captUri = currentUri;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (pb.currentTrack?['uri'] != captUri) return;
            _updatePalette(
              imageBytes: pb.currentImageBytes,
              imageUrl: pb.currentTrack?['imageUrl'] ?? widget.artworkUrl,
              trackUri: captUri,
            );
          });
        }

        final screenHeight = MediaQuery.sizeOf(context).height;
        final dragProgress = (_dragOffset / screenHeight).clamp(0.0, 1.0);

        return GestureDetector(
          onVerticalDragUpdate: widget.insideSheet ? null : _onDragUpdate,
          onVerticalDragEnd: widget.insideSheet ? null : _onDragEnd,
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Opacity(
              opacity: (1 - dragProgress * 1.2).clamp(0.4, 1.0),
              child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: context.colors.surface),

              if (context.watch<AppearanceProvider>().artworkBackground)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _swipeProgress,
                      builder: (context, swipe, _) {
                        final surface = context.colors.surface;

                        final neighbour = swipe > 0
                            ? pb.dominantColorForUrl(
                                pb.nextQueueTrack?['imageUrl'] as String?)
                            : pb.dominantColorForUrl(
                                pb.previousQueueTrack?['imageUrl'] as String?);

                        final progress = swipe.abs().clamp(0.0, 1.0);
                        final Color base;
                        if (neighbour == null) {
                          base = Color.lerp(_displayDominant, surface, progress)!;
                        } else if (progress < 0.5) {
                          base = Color.lerp(
                              _displayDominant, surface, progress * 2)!;
                        } else {
                          base = Color.lerp(
                              surface, neighbour, (progress - 0.5) * 2)!;
                        }

                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.lerp(base, surface, 0.25)!,
                                Color.lerp(base, surface, 0.72)!,
                                surface,
                              ],
                              stops: const [0.0, 0.5, 0.9],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artSize = (constraints.maxHeight * 0.42)
                        .clamp(140.0, constraints.maxWidth - 96);

                    return Column(
                      children: [
                        _Header(
                          onClose: () => Navigator.of(context).pop(),
                          topInset: widget.insideSheet
                              ? MediaQueryData.fromView(View.of(context))
                                      .viewPadding
                                      .top +
                                  AppSpacing.sm
                              : 0,
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _rise(
                                    delay: 0,
                                    offset: 40,
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: artSize,
                                      child: ArtworkPager(
                                        key: _pagerKey,
                                        size: artSize,
                                        currentKey: currentUri ?? '',
                                        current: ArtworkSource(
                                          bytes: imageBytes,
                                          url: imageUrl as String?,
                                        ),
                                        previous: _neighbourSource(
                                            pb.previousQueueTrack),
                                        next: _neighbourSource(
                                            pb.nextQueueTrack),
                                        progress: _swipeProgress,
                                        onNext: () {
                                          _adoptNeighbourColor(pb, 1);
                                          pb.goToNext();
                                        },
                                        onPrevious: () {
                                          _adoptNeighbourColor(pb, -1);
                                          pb.goToPrevious();
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _rise(
                                    delay: 0.12,
                                    child: _TrackInfo(title: title, artist: artist),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            0,
                            AppSpacing.lg,
                            AppSpacing.lg,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _rise(
                                delay: 0.2,
                                offset: 20,
                                child: _NowPlayingProgressBar(
                                positionMs: _positionMs,
                                durationMs: duration,
                                accentColor: _displayVibrant,
                                onSeekStart: () => setState(() => _dragging = true),
                                onSeekChanged: (v) => setState(() => _positionMs = v),
                                onSeekEnd: (v) {
                                  setState(() {
                                    _positionMs = v;
                                    _dragging = false;
                                  });
                                  pb.seekTo(v);
                                },
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _rise(
                                delay: 0.28,
                                offset: 16,
                                child: _Controls(
                                isPlaying: pb.isPlaying,
                                accentColor: _displayVibrant,
                                onPrevious: () => _slideTo(-1, pb.goToPrevious),
                                onNext: () => _slideTo(1, pb.goToNext),
                                onToggle: pb.togglePlay,
                                isShuffle: pb.shuffleActive,
                                repeatMode: pb.repeatMode,
                                onShuffle: () => pb.setShuffle(!pb.shuffleActive),
                                onRepeat: pb.cycleRepeatMode,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
              ),
            ),
          ),
        );
      },
    );
  }

}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, this.topInset = 0});

  final VoidCallback onClose;

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        topInset,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            color: Colors.white,
            tooltip: 'Свернуть',
          ),
          Expanded(
            child: Text(
              'Сейчас играет',
              textAlign: TextAlign.center,
              style: context.texts.labelLarge?.copyWith(
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.title, required this.artist});

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.texts.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.isPlaying,
    required this.accentColor,
    required this.onPrevious,
    required this.onNext,
    required this.onToggle,
    required this.isShuffle,
    required this.repeatMode,
    required this.onShuffle,
    required this.onRepeat,
  });

  final bool isPlaying;
  final Color accentColor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final bool isShuffle;
  final String repeatMode;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ModeButton(
          icon: Icons.shuffle_rounded,
          isActive: isShuffle,
          accentColor: accentColor,
          tooltip: isShuffle ? 'Перемешивание включено' : 'Перемешать',
          onPressed: onShuffle,
        ),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded, size: 40),
          color: Colors.white,
          tooltip: 'Предыдущий трек',
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.5),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            onPressed: onToggle,
            iconSize: 44,
            padding: const EdgeInsets.all(AppSpacing.md),
            tooltip: isPlaying ? 'Пауза' : 'Воспроизвести',
            icon: AnimatedSwitcher(
              duration: AppMotion.short,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(parent: animation, curve: AppMotion.enter),
                child: child,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(isPlaying),
                color: Colors.black87,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded, size: 40),
          color: Colors.white,
          tooltip: 'Следующий трек',
        ),
        _ModeButton(
          icon: repeatMode == 'track' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          isActive: repeatMode != 'off',
          accentColor: accentColor,
          tooltip: switch (repeatMode) {
            'track' => 'Повтор одного трека',
            'context' => 'Повтор списка',
            _ => 'Повтор выключен',
          },
          onPressed: onRepeat,
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.isActive,
    required this.accentColor,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool isActive;
  final Color accentColor;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 24),
      color: isActive ? Colors.white : Colors.white38,
      style: IconButton.styleFrom(
        backgroundColor: isActive ? accentColor.withValues(alpha: 0.28) : null,
      ),
    );
  }
}

class _NowPlayingProgressBar extends StatelessWidget {
  const _NowPlayingProgressBar({
    required this.positionMs,
    required this.durationMs,
    required this.accentColor,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final int positionMs;
  final int durationMs;
  final Color accentColor;
  final VoidCallback onSeekStart;
  final ValueChanged<int> onSeekChanged;
  final ValueChanged<int> onSeekEnd;

  String _format(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final safeDuration = durationMs > 0 ? durationMs : 1;
    final value = positionMs.clamp(0, safeDuration).toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
            overlayColor: accentColor.withValues(alpha: 0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value,
            max: safeDuration.toDouble(),
            onChangeStart: (_) => onSeekStart(),
            onChanged: (v) => onSeekChanged(v.round()),
            onChangeEnd: (v) => onSeekEnd(v.round()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(positionMs),
                style: context.timecode(color: Colors.white70),
              ),
              Text(
                _format(durationMs),
                style: context.timecode(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }
}