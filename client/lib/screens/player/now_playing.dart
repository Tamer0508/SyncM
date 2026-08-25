import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../providers/appearance_provider.dart';
import '../../providers/playback_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/add_to_playlist_sheet.dart';
import 'artwork_pager.dart';
import '../../utils/duration_text.dart';
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

  static bool _isOpen = false;

  static bool get isOpen => _isOpen;

  static Future<void> open(
    BuildContext context, {
    String? title,
    String? artist,
    String? artworkUrl,
  }) {
    if (_isOpen) return Future<void>.value();
    _isOpen = true;

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
    ).whenComplete(() => _isOpen = false);
  }

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  /// Позиция, которую пользователь тянет пальцем. null — показываем живую
  /// позицию из провайдера.
  final ValueNotifier<int?> _seekPreview = ValueNotifier<int?>(null);

  late AnimationController _colorAnimController;
  late Animation<Color?> _colorDominantAnim;
  late Animation<Color?> _colorVibrantAnim;

  Color _targetDominant = Colors.deepPurple;
  Color _targetVibrant = Colors.purpleAccent;

  // Текущий цвет читается прямо из анимации, поэтому перекраска
  // перестраивает только фон и цветные элементы, а не весь экран.
  Color get _displayDominant => _colorDominantAnim.value ?? _targetDominant;
  Color get _displayVibrant => _colorVibrantAnim.value ?? _targetVibrant;

  String? _colorTrackId;

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

  String? _swipeFromPreviousUrl;
  String? _swipeFromNextUrl;

  final GlobalKey<ArtworkPagerState> _pagerKey = GlobalKey();

  final Set<String> _warmedArtwork = {};

  void _warmUpcoming(List<String> urls, double size) {
    if (!_entered || size <= 0) return;

    final ratio = MediaQuery.devicePixelRatioOf(context);

    final fresh = urls
        .where((url) => _warmedArtwork.add('$url@${size.round()}@$ratio'))
        .toList();
    if (fresh.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in fresh) {
        precacheImage(
          AppNetworkImage.providerFor(
            url,
            width: size,
            height: size,
            devicePixelRatio: ratio,
          ),
          context,
          onError: (_, _) {},
        );
      }
    });
  }

  ArtworkSlot? _neighbourSlot(Map<String, dynamic>? track) {
    final trackId = track?['uri'] as String?;
    if (trackId == null || trackId.isEmpty) return null;

    final url = track?['imageUrl'] as String?;
    return ArtworkSlot(
      trackId: trackId,
      source: ArtworkSource(url: url),
    );
  }

  void _adoptNeighbourColor(PlaybackProvider pb, int direction) {
    final track =
        direction > 0 ? pb.nextQueueTrack : pb.previousQueueTrack;
    final trackId = track?['uri'] as String?;

    _handOverColorTo(trackId);

    final url = track?['imageUrl'] as String?;

    final palette = url == null ? null : pb.paletteCache[url];
    if (palette != null) {
      _applyTrackColors(
        trackId,
        palette.dominantColor?.color ?? _displayDominant,
        palette.vibrantColor?.color ??
            palette.lightVibrantColor?.color ??
            _displayVibrant,
        animate: false,
      );
      return;
    }

    final dominant = pb.dominantColorForUrl(url);
    if (dominant == null) return;

    _applyTrackColors(trackId, dominant, _displayVibrant, animate: false);
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

    _entrance = AnimationController(vsync: this, duration: AppMotion.page)
      ..forward();

    // Своего таймера позиции здесь нет: её тикает один общий механизм в
    // провайдере, а слушает только полоса прогресса.

    _colorAnimController = AnimationController(
      vsync: this,
      duration: AppMotion.tint,
    );
    _colorDominantAnim = ColorTween(begin: _targetDominant, end: _targetDominant)
        .animate(_colorAnimController);
    _colorVibrantAnim = ColorTween(begin: _targetVibrant, end: _targetVibrant)
        .animate(_colorAnimController);
  }

  @override
  void dispose() {
    if (widget.insideSheet) NowPlayingScreen._isOpen = false;

    _routeAnimation?.removeStatusListener(_onRouteAnimation);
    _swipeProgress.dispose();
    _seekPreview.dispose();
    _entrance.dispose();
    _colorAnimController.dispose();
    super.dispose();
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

  void _handOverColorTo(String? trackId) {
    if (_colorTrackId == trackId) return;

    _colorTrackId = trackId;

    // Расчёты палитры прежнего трека с этого момента недействительны.
    _paletteRequest++;
  }
  void _applyTrackColors(
    String? trackId,
    Color dominant,
    Color vibrant, {
    bool animate = true,
  }) {
    if (trackId != _colorTrackId) return;

    if (_targetDominant == dominant && _targetVibrant == vibrant) return;

    _targetDominant = dominant;
    _targetVibrant = vibrant;

    _colorDominantAnim = ColorTween(begin: _displayDominant, end: dominant)
        .animate(_colorAnimController);
    _colorVibrantAnim = ColorTween(begin: _displayVibrant, end: vibrant)
        .animate(_colorAnimController);

    if (!animate) {
      _colorAnimController.value = 1;
      return;
    }

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
      // У трека нет обложки вообще — это его собственный цвет, а не заглушка
      // на время расчёта.
      _applyTrackColors(trackUri, Colors.deepPurple, Colors.purpleAccent);
      return;
    }

    final provider = Provider.of<PlaybackProvider>(context, listen: false);

    final String? cacheKey = imageUrl ?? trackUri;

    if (cacheKey != null && provider.paletteCache.containsKey(cacheKey)) {
      _applyPalette(provider.paletteCache[cacheKey]!, trackUri);
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

    final palette = await provider.paletteFor(
      imageUrl: imageUrl,
      imageBytes: imageBytes,
      fallbackKey: trackUri,
    );

    if (palette == null || !mounted || request != _paletteRequest) return;

    _applyPalette(palette, trackUri);
  }

  void _applyPalette(PaletteGenerator p, String? trackUri) {
    if (!mounted) return;

    _applyTrackColors(
      trackUri,
      p.dominantColor?.color ?? Colors.deepPurple,
      p.vibrantColor?.color ??
          (p.lightVibrantColor?.color ?? Colors.purpleAccent),
    );
  }

  Color _backgroundAt(double t, {required bool artworkBackground}) {
    final surface = context.colors.surface;
    if (!artworkBackground) return surface;
    return Color.lerp(_displayDominant, surface, t)!;
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
        final currentUri = track?['uri'] as String?;

        final artworkTrackId = currentUri ?? imageUrl ?? '';

        // Соседей опрашиваем один раз за перестроение экрана, а не на
        // каждом кадре свайпа.
        final previousTrack = pb.previousQueueTrack;
        final nextTrack = pb.nextQueueTrack;
        final previousArtworkUrl = previousTrack?['imageUrl'] as String?;
        final nextArtworkUrl = nextTrack?['imageUrl'] as String?;

        if (currentUri != _lastTrackUri) {
          _lastTrackUri = currentUri;

          _handOverColorTo(currentUri);
        }

        final imageUrlNow = pb.currentTrack?['imageUrl'] as String? ?? widget.artworkUrl;

        final int imageSig = imageBytes != null
            ? _imageSignature(imageBytes, currentUri)
            : Object.hash(imageUrlNow, currentUri);

        if (imageSig != _lastPaletteImageSig) {
          _lastPaletteImageSig = imageSig;
          final captUri = currentUri;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _colorTrackId != captUri) return;
            _updatePalette(
              imageBytes: pb.currentImageBytes,
              imageUrl: pb.currentTrack?['imageUrl'] ?? widget.artworkUrl,
              trackUri: captUri,
            );
          });
        }

        final screenHeight = MediaQuery.sizeOf(context).height;
        final dragProgress = (_dragOffset / screenHeight).clamp(0.0, 1.0);

        final artworkBackground =
            context.watch<AppearanceProvider>().artworkBackground;

        final controlsForeground = _Foreground.on(context.colors.surface);

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

              if (artworkBackground)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      // Кадр свайпа и перекраска обложки — единственные
                      // причины пересчитать фон. Цвета соседей берутся из
                      // кэша палитр заранее, а не на каждом кадре.
                      animation: Listenable.merge(
                        [_swipeProgress, _colorAnimController, pb.paletteVersion],
                      ),
                      builder: (context, _) {
                        final swipe = _swipeProgress.value;
                        final surface = context.colors.surface;

                        if (swipe == 0) {
                          _swipeFromPreviousUrl = previousArtworkUrl;
                          _swipeFromNextUrl = nextArtworkUrl;
                        }

                        final neighbour = pb.dominantColorForUrl(swipe > 0
                            ? _swipeFromNextUrl
                            : _swipeFromPreviousUrl);

                        final progress = swipe.abs().clamp(0.0, 1.0);
                        final Color base;
                        if (neighbour == null) {
                          base = _displayDominant;
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

                    _warmUpcoming(pb.neighbourArtworkUrls, artSize);

                    return Column(
                      children: [
                        AnimatedBuilder(
                          animation: _colorAnimController,
                          builder: (context, _) => _Header(
                            fg: _Foreground.on(_backgroundAt(
                              0.25,
                              artworkBackground: artworkBackground,
                            )),
                            onClose: () => Navigator.of(context).pop(),
                            topInset: widget.insideSheet
                                ? MediaQueryData.fromView(View.of(context))
                                        .viewPadding
                                        .top +
                                    AppSpacing.sm
                                : 0,
                          ),
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
                                        current: ArtworkSlot(
                                          trackId: artworkTrackId,
                                          source: ArtworkSource(
                                            bytes: imageBytes,
                                            url: imageUrl,
                                          ),
                                        ),
                                        previous:
                                            _neighbourSlot(previousTrack),
                                        next: _neighbourSlot(nextTrack),
                                        switching: pb.isSwitchingTrack,
                                        progress: _swipeProgress,
                                        onNext: () {
                                          if (pb.isSwitchingTrack) return false;
                                          _adoptNeighbourColor(pb, 1);
                                          pb.goToNext();
                                          return true;
                                        },
                                        onPrevious: () {
                                          if (pb.isSwitchingTrack) return false;
                                          _adoptNeighbourColor(pb, -1);
                                          pb.goToPrevious();
                                          return true;
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _rise(
                                    delay: 0.12,
                                    child: AnimatedBuilder(
                                      animation: _colorAnimController,
                                      builder: (context, _) => _TrackInfo(
                                        title: title,
                                        artist: artist,
                                        fg: _Foreground.on(_backgroundAt(
                                          0.8,
                                          artworkBackground: artworkBackground,
                                        )),
                                      ),
                                    ),
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
                                // Позицию и цвет слушает только сама полоса:
                                // тик прогресса не трогает остальной экран.
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    pb.positionNotifier,
                                    _seekPreview,
                                    _colorAnimController,
                                  ]),
                                  builder: (context, _) {
                                    final position = _seekPreview.value ??
                                        pb.positionNotifier.value;

                                    return _NowPlayingProgressBar(
                                      positionMs: position,
                                      durationMs: duration,
                                      accentColor: _displayVibrant,
                                      fg: controlsForeground,
                                      onSeekStart: () => _seekPreview.value =
                                          pb.positionNotifier.value,
                                      onSeekChanged: (v) =>
                                          _seekPreview.value = v,
                                      onSeekEnd: (v) {
                                        _seekPreview.value = null;
                                        pb.seekTo(v);
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _rise(
                                delay: 0.28,
                                offset: 16,
                                child: AnimatedBuilder(
                                  animation: _colorAnimController,
                                  builder: (context, _) => _Controls(
                                    isPlaying: pb.isPlaying,
                                    accentColor: _displayVibrant,
                                    fg: controlsForeground,
                                    onPrevious: () =>
                                        _slideTo(-1, pb.goToPrevious),
                                    onNext: () => _slideTo(1, pb.goToNext),
                                    onToggle: pb.togglePlay,
                                    isShuffle: pb.shuffleActive,
                                    repeatMode: pb.repeatMode,
                                    onShuffle: () =>
                                        pb.setShuffle(!pb.shuffleActive),
                                    onRepeat: pb.cycleRepeatMode,
                                  ),
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

class _Foreground {
  const _Foreground._({required this.primary, required this.contrast});

  /// Основной текст и иконки.
  final Color primary;

  /// То, что лежит поверх [primary] — иконка на белом круге play/pause.
  final Color contrast;

  Color get muted => primary.withValues(alpha: 0.70);
  Color get faint => primary.withValues(alpha: 0.38);
  Color get track => primary.withValues(alpha: 0.24);

  static const _onDark =
      _Foreground._(primary: Colors.white, contrast: Colors.black87);
  static const _onLight =
      _Foreground._(primary: Color(0xFF1A1A1A), contrast: Colors.white);

  factory _Foreground.on(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? _onDark
          : _onLight;
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.fg, this.topInset = 0});

  final VoidCallback onClose;

  final _Foreground fg;

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
            color: fg.primary,
            tooltip: L.of(context).commonCollapse,
          ),
          Expanded(
            child: Text(
              L.of(context).playerNowPlayingLabel,
              textAlign: TextAlign.center,
              style: context.texts.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: fg.muted,
              ),
            ),
          ),
          _AddCurrentTrackButton(fg: fg),
        ],
      ),
    );
  }
}

class _AddCurrentTrackButton extends StatelessWidget {
  const _AddCurrentTrackButton({required this.fg});

  final _Foreground fg;

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlaybackProvider, Map<String, dynamic>?>(
      (pb) => pb.currentTrack,
    );

    if (track == null) return const SizedBox(width: 48);

    return IconButton(
      onPressed: () => showAddToPlaylistSheet(context, {
        'uri': track['uri'],
        'name': track['title'] ?? track['name'],
        'artist': track['artist'],
        'imageUrl': track['imageUrl'],
        'durationMs': track['durationMs'],
      }),
      icon: const Icon(Icons.playlist_add_rounded, size: 26),
      color: fg.primary,
      tooltip: L.of(context).addToPlaylistTitle,
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({
    required this.title,
    required this.artist,
    required this.fg,
  });

  final String title;
  final String artist;
  final _Foreground fg;

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
            style: context.texts.headlineMedium?.copyWith(color: fg.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleMedium?.copyWith(color: fg.muted),
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
    required this.fg,
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
  final _Foreground fg;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final bool isShuffle;
  final String repeatMode;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  static const double _tightControlsWidth = 340;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildRow(
        context,
        playPadding: constraints.maxWidth >= _tightControlsWidth
            ? AppSpacing.md
            : AppSpacing.sm,
      ),
    );
  }

  Widget _buildRow(BuildContext context, {required double playPadding}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ModeButton(
          icon: Icons.shuffle_rounded,
          isActive: isShuffle,
          accentColor: accentColor,
          fg: fg,
          tooltip: isShuffle ? L.of(context).playerShuffleOn : L.of(context).playerShuffle,
          onPressed: onShuffle,
        ),
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded, size: 40),
          color: fg.primary,
          tooltip: L.of(context).playerPrevious,
        ),
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fg.primary,
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
            padding: EdgeInsets.all(playPadding),
            tooltip: isPlaying ? L.of(context).playerPause : L.of(context).playerPlay,
            icon: AnimatedSwitcher(
              duration: AppMotion.short,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(parent: animation, curve: AppMotion.enter),
                child: child,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(isPlaying),
                color: fg.contrast,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded, size: 40),
          color: fg.primary,
          tooltip: L.of(context).playerNext,
        ),
        _ModeButton(
          icon: repeatMode == 'track' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          isActive: repeatMode != 'off',
          accentColor: accentColor,
          fg: fg,
          tooltip: switch (repeatMode) {
            'track' => L.of(context).playerRepeatOne,
            'context' => L.of(context).playerRepeatAll,
            _ => L.of(context).playerRepeatOff,
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
    required this.fg,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final bool isActive;
  final Color accentColor;
  final _Foreground fg;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 24),
      color: isActive ? fg.primary : fg.faint,
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
    required this.fg,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
  });

  final int positionMs;
  final int durationMs;
  final Color accentColor;
  final _Foreground fg;
  final VoidCallback onSeekStart;
  final ValueChanged<int> onSeekChanged;
  final ValueChanged<int> onSeekEnd;

  @override
  Widget build(BuildContext context) {
    final safeDuration = durationMs > 0 ? durationMs : 1;
    final value = positionMs.clamp(0, safeDuration).toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: fg.track,
            thumbColor: fg.primary,
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
                formatDuration(positionMs),
                style: context.timecode(color: fg.muted),
              ),
              Text(
                formatDuration(durationMs),
                style: context.timecode(color: fg.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}