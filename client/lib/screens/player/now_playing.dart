import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';

class _AnimatedGlowBackground extends StatefulWidget {
  final Color dominantColor;
  final Color vibrantColor;

  const _AnimatedGlowBackground({
    Key? key,
    required this.dominantColor,
    required this.vibrantColor,
  }) : super(key: key);

  @override
  State<_AnimatedGlowBackground> createState() => _AnimatedGlowBackgroundState();
}

class _AnimatedGlowBackgroundState extends State<_AnimatedGlowBackground>
    with TickerProviderStateMixin {
  late final AnimationController _circlesController;
  late final AnimationController _particlesController;
  final _random = Random(42);
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _circlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _particlesController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _particles = List.generate(60, (_) => _Particle(_random));
  }

  @override
  void dispose() {
    _circlesController.dispose();
    _particlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseDominant = widget.dominantColor;
    final baseVibrant = widget.vibrantColor;

    final circleColors = [
      baseDominant.withOpacity(isDark ? 0.45 : 0.5),
      baseVibrant.withOpacity(isDark ? 0.35 : 0.4),
      baseDominant.withOpacity(isDark ? 0.25 : 0.35),
    ];

    final particleBaseColor =
        isDark ? baseVibrant.withOpacity(0.45) : baseDominant.withOpacity(0.28);
    final lineColor =
        isDark ? baseVibrant.withOpacity(0.15) : baseDominant.withOpacity(0.12);

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _circlesController,
            builder: (_, __) => CustomPaint(
              painter: _CircleLayerPainter(
                animationValue: _circlesController.value,
                colors: circleColors,
              ),
              size: Size.infinite,
            ),
          ),
        ),
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _particlesController,
            builder: (_, __) => CustomPaint(
              painter: _ParticleNetworkPainter(
                animationValue: _particlesController.value,
                particles: _particles,
                particleColor: particleBaseColor,
                lineColor: lineColor,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _Particle {
  double x, y;
  final double speed, radius, opacity, phase, connectionRadius;
  _Particle(Random random)
      : x = random.nextDouble(),
        y = random.nextDouble(),
        speed = 0.08 + random.nextDouble() * 0.06,
        radius = 1.4 + random.nextDouble() * 2.8,
        opacity = 0.35 + random.nextDouble() * 0.45,
        phase = random.nextDouble() * 2 * pi,
        connectionRadius = 0.12 + random.nextDouble() * 0.14;
}

class _ParticleNetworkPainter extends CustomPainter {
  final double animationValue;
  final List<_Particle> particles;
  final Color particleColor;
  final Color lineColor;

  _ParticleNetworkPainter({
    required this.animationValue,
    required this.particles,
    required this.particleColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final particlePaint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final positions = <Offset>[];

    for (final p in particles) {
      final dx = (animationValue * p.speed * 2 * pi + p.phase);
      final dy = (animationValue * p.speed * 3 * pi + p.phase * 1.7);
      final nx = (p.x + 0.60 * sin(dx)) % 1.0;
      final ny = (p.y + 0.60 * cos(dy)) % 1.0;
      positions.add(Offset(nx * size.width, ny * size.height));
    }

    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        final maxDist = size.width * particles[i].connectionRadius;
        if (d < maxDist) {
          final opacity = (1 - d / maxDist) * 0.4;
          linePaint.color = lineColor.withOpacity(opacity.clamp(0.0, 1.0));
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }

    for (int i = 0; i < particles.length; i++) {
      particlePaint.color = particleColor.withOpacity(particles[i].opacity);
      canvas.drawCircle(positions[i], particles[i].radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(_ParticleNetworkPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.particleColor != particleColor ||
      oldDelegate.lineColor != lineColor;
}

class _CircleLayerPainter extends CustomPainter {
  final double animationValue;
  final List<Color> colors;

  _CircleLayerPainter({required this.animationValue, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55);
    final positions = [
      Offset(size.width * 0.25, size.height * 0.3),
      Offset(size.width * 0.75, size.height * 0.65),
      Offset(size.width * 0.5, size.height * 0.5),
    ];
    final radii = [
      160.0 + 40 * sin(animationValue * 2 * pi),
      200.0 + 60 * cos(animationValue * 2 * pi + 1),
      180.0 + 50 * sin(animationValue * 2 * pi + 2),
    ];
    for (int i = 0; i < positions.length; i++) {
      final t = animationValue * 2 * pi;
      final cx = positions[i].dx + 30 * sin(t + i);
      final cy = positions[i].dy + 30 * cos(t + i * 1.3);
      paint.color = colors[i % colors.length];
      canvas.drawCircle(Offset(cx, cy), radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(_CircleLayerPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue;
}

class NowPlayingScreen extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? artworkUrl;

  const NowPlayingScreen({Key? key, this.title, this.artist, this.artworkUrl})
      : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  int _positionMs = 0;
  bool _dragging = false;

  late AnimationController _artworkFadeController;
  late Animation<double> _artworkFadeAnimation;

  late AnimationController _colorAnimController;
  late Animation<Color?> _colorDominantAnim;
  late Animation<Color?> _colorVibrantAnim;

  Color _displayDominant = Colors.deepPurple;
  Color _displayVibrant = Colors.purpleAccent;
  Color _targetDominant = Colors.deepPurple;
  Color _targetVibrant = Colors.purpleAccent;

  final Map<String, PaletteGenerator> _paletteCache = {};
  Uint8List? _lastImageBytes;
  String? _lastImageUrl;
  String? _lastTrackUri;
  Uint8List? _previousImageBytes;

  @override
  void initState() {
    super.initState();
    _positionMs =
        Provider.of<PlaybackProvider>(context, listen: false).positionMs;
    _startTimer();

    _artworkFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _artworkFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _artworkFadeController, curve: Curves.easeInOut),
    );
    _artworkFadeController.forward();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
    _artworkFadeController.dispose();
    _colorAnimController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final pb = Provider.of<PlaybackProvider>(context, listen: false);
      if (pb.isPlaying && !_dragging) {
        setState(() {
          _positionMs = (_positionMs + 1000).clamp(0, pb.durationMs);
        });
      }
    });
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _setTargetColors(Color dominant, Color vibrant) {
    if (_targetDominant == dominant && _targetVibrant == vibrant) return;
    _targetDominant = dominant;
    _targetVibrant = vibrant;

    _colorDominantAnim = ColorTween(
      begin: _displayDominant,
      end: dominant,
    ).animate(_colorAnimController);
    _colorVibrantAnim = ColorTween(
      begin: _displayVibrant,
      end: vibrant,
    ).animate(_colorAnimController);

    _colorAnimController
      ..reset()
      ..forward();
  }

  Future<void> _updatePalette({
    Uint8List? imageBytes,
    String? imageUrl,
  }) async {
    if (imageBytes == null && (imageUrl == null || imageUrl.isEmpty)) {
      _setTargetColors(Colors.deepPurple, Colors.purpleAccent);
      return;
    }

    final provider = Provider.of<PlaybackProvider>(context, listen: false);
    if (imageUrl != null && provider.paletteCache.containsKey(imageUrl)) {
      final p = provider.paletteCache[imageUrl]!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setTargetColors(
          p.dominantColor?.color ?? Colors.deepPurple,
          p.vibrantColor?.color ??
              (p.lightVibrantColor?.color ?? Colors.purpleAccent),
        );
      });
      return;
    }

    try {
      late ImageProvider providerImg;
      if (imageBytes != null) {
        providerImg = MemoryImage(imageBytes);
      } else {
        providerImg = NetworkImage(imageUrl!);
      }
      final palette = await PaletteGenerator.fromImageProvider(
        providerImg,
        size: const Size(200, 200),
        maximumColorCount: 16,
      );
      if (imageUrl != null) {
        provider.paletteCache[imageUrl] = palette;
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setTargetColors(
          palette.dominantColor?.color ?? Colors.deepPurple,
          palette.vibrantColor?.color ??
              (palette.lightVibrantColor?.color ?? Colors.purpleAccent),
        );
      });
    } catch (e) {
      print('Palette error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Consumer<PlaybackProvider>(
      builder: (ctx, pb, _) {
        final title =
            pb.currentTrack?['title'] ?? widget.title ?? 'Unknown Title';
        final artist =
            pb.currentTrack?['artist'] ?? widget.artist ?? 'Unknown Artist';
        final duration = pb.durationMs;
        final imageBytes = pb.currentImageBytes;
        final imageUrl = pb.currentTrack?['imageUrl'] ?? widget.artworkUrl;

        final bool trackChanged = pb.currentTrack?['uri'] != _lastTrackUri;
        final bool artworkChanged =
            imageBytes != _lastImageBytes || imageUrl != _lastImageUrl;

        if (trackChanged) {
          _lastTrackUri = pb.currentTrack?['uri'];
          _previousImageBytes = _lastImageBytes;

          final cachedPalette = pb.currentTrack?['imageUrl'] != null
              ? pb.paletteCache[pb.currentTrack!['imageUrl']]
              : null;
          if (cachedPalette != null) {
            _setTargetColors(
              cachedPalette.dominantColor?.color ?? Colors.blueGrey.shade800,
              cachedPalette.vibrantColor?.color ?? Colors.blueGrey.shade600,
            );
          } else {
            _setTargetColors(
                Colors.blueGrey.shade800, Colors.blueGrey.shade600);
          }
          _updatePalette(imageBytes: imageBytes, imageUrl: imageUrl);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _artworkFadeController.reset();
            _artworkFadeController.forward();
          });
        }

        if (artworkChanged) {
          _lastImageBytes = imageBytes;
          _lastImageUrl = imageUrl;
          if (!trackChanged) {
            _updatePalette(imageBytes: imageBytes, imageUrl: imageUrl);
          }
        }

        if (isDesktop &&
            !_dragging &&
            pb.positionMs > 0 &&
            (pb.positionMs - _positionMs).abs() > 2000) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _positionMs = pb.positionMs);
          });
        }

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              _AnimatedGlowBackground(
                dominantColor: _displayDominant,
                vibrantColor: _displayVibrant,
              ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 32, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          Text(
                            'NOW PLAYING',
                            style: theme.textTheme.labelLarge?.copyWith(
                              letterSpacing: 3,
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Обложка
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 48),
                      height: isDesktop
                          ? MediaQuery.of(context).size.height * 0.28
                          : MediaQuery.of(context).size.width * 0.58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: _displayDominant.withOpacity(0.4),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 20),
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: -2,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_previousImageBytes != null && trackChanged)
                              FadeTransition(
                                opacity: Tween<double>(begin: 1.0, end: 0.0)
                                    .animate(_artworkFadeController),
                                child: Image.memory(
                                  _previousImageBytes!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            FadeTransition(
                              opacity: _artworkFadeAnimation,
                              child: imageBytes != null
                                  ? Image.memory(imageBytes,
                                      fit: BoxFit.cover)
                                  : imageUrl != null && imageUrl.isNotEmpty
                                      ? Image.network(imageUrl,
                                          fit: BoxFit.cover)
                                      : Container(
                                          color: Colors.white12,
                                          child: Icon(Icons.music_note,
                                              size: 80,
                                              color: Colors.white38),
                                        ),
                            ),
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                    width: 1.5,
                                  ),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.08),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.montserrat(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist,
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Прогресс-бар (исправленный, без обрезания)
                    _NowPlayingProgressBar(
                      positionMs: _positionMs,
                      durationMs: duration,
                      activeColor: _displayVibrant,
                      onSeek: (ms) {
                        setState(() => _positionMs = ms);
                        pb.seekTo(ms);
                      },
                      formatMs: _formatMs,
                    ),
                    const SizedBox(height: 20),
                    // Кнопки управления (стиль как в правой панели)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(Icons.shuffle,
                                color: pb.shuffleActive
                                    ? _displayVibrant
                                    : Colors.white70,
                                size: 26),
                            onPressed: () => pb.setShuffle(!pb.shuffleActive),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                            onPressed: () {
                              setState(() => _positionMs = 0);
                              pb.skipPrevious();
                            },
                          ),
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _displayVibrant,
                            ),
                            child: IconButton(
                              icon: Icon(
                                pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              onPressed: () => pb.togglePlay(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                            onPressed: () {
                              setState(() => _positionMs = 0);
                              pb.skipNext();
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              pb.repeatMode == 'track' ? Icons.repeat_one : Icons.repeat,
                              color: pb.repeatActive ? _displayVibrant : Colors.white70,
                              size: 26,
                            ),
                            onPressed: () => pb.cycleRepeatMode(),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NowPlayingProgressBar extends StatefulWidget {
  final int positionMs;
  final int durationMs;
  final Color activeColor;
  final Function(int ms) onSeek;
  final String Function(int ms) formatMs;

  const _NowPlayingProgressBar({
    Key? key,
    required this.positionMs,
    required this.durationMs,
    required this.activeColor,
    required this.onSeek,
    required this.formatMs,
  }) : super(key: key);

  @override
  State<_NowPlayingProgressBar> createState() => _NowPlayingProgressBarState();
}

class _NowPlayingProgressBarState extends State<_NowPlayingProgressBar> {
  double _localValue = 0.0;
  bool _draggingLocal = false;

  @override
  Widget build(BuildContext context) {
    final double fraction = widget.durationMs > 0
        ? (_draggingLocal
                ? _localValue
                : widget.positionMs / widget.durationMs)
            .clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          GestureDetector(
            onTapDown: (details) {
              _draggingLocal = true;
              _updateFromTap(details);
            },
            onTapUp: (_) {
              _draggingLocal = false;
              widget.onSeek((_localValue * widget.durationMs).toInt());
            },
            onHorizontalDragUpdate: (details) {
              if (!_draggingLocal) return;
              final box = context.findRenderObject() as RenderBox;
              final localX = details.localPosition.dx.clamp(0.0, box.size.width);
              setState(() {
                _localValue = localX / box.size.width;
              });
            },
            child: SizedBox(
              height: 24, // достаточно места для ползунка
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Фоновая дорожка
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 4,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // Активная дорожка
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: widget.activeColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Ползунок
                  Positioned(
                    left: (fraction * (MediaQuery.of(context).size.width - 48))
                        .clamp(0.0, MediaQuery.of(context).size.width - 48),
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: widget.activeColor.withOpacity(0.8),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.formatMs(widget.positionMs),
                  style: GoogleFonts.montserrat(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.formatMs(widget.durationMs),
                  style: GoogleFonts.montserrat(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateFromTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final localX = details.localPosition.dx.clamp(0.0, box.size.width);
    setState(() {
      _localValue = localX / box.size.width;
    });
    widget.onSeek((_localValue * widget.durationMs).toInt());
  }
}