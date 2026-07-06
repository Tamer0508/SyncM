import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';
import '../../widgets/app_icon_button.dart';

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
  void didUpdateWidget(_AnimatedGlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    // При смене трека цвета в widget уже обновлены (через _setTargetColors
    // родителя), но CustomPaint перерисовывается только на тике контроллера —
    // раз в 60 секунд. Форсируем rebuild немедленно.
    if (oldWidget.dominantColor != widget.dominantColor ||
        oldWidget.vibrantColor != widget.vibrantColor) {
      setState(() {});
    }
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
  bool _dragging = false; // Теперь активно используется!

  int? _lastSyncPosition;

  late AnimationController _colorAnimController;
  late Animation<Color?> _colorDominantAnim;
  late Animation<Color?> _colorVibrantAnim;

  Color _displayDominant = Colors.deepPurple;
  Color _displayVibrant = Colors.purpleAccent;
  Color _targetDominant = Colors.deepPurple;
  Color _targetVibrant = Colors.purpleAccent;

  String? _lastTrackUri;
  // Сигнатура обложки, по которой уже посчитана палитра. Нужна, чтобы
  // поймать ПОЗДНЮЮ загрузку картинки: при обычном переключении uri меняется
  // раньше, чем догружаются байты обложки, и без этого поля палитра осталась
  // бы на нейтральных цветах до следующей смены трека.
  int? _lastPaletteImageSig;

  @override
  void initState() {
    super.initState();
    _positionMs = Provider.of<PlaybackProvider>(context, listen: false).positionMs;
    _startTimer();

    _colorAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
    _colorAnimController.dispose();
    super.dispose();
  }

  void _startTimer() {
  _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    if (!mounted) return;
    final pb = Provider.of<PlaybackProvider>(context, listen: false);

    if (_dragging) return; // пока тащим ползунок — не трогаем позицию

    if (pb.sessionMode) {
      // Фаза 4.3: в сессии позиция считается провайдером от серверного
      // времени — просто отражаем её, чтобы прогресс-бар был синхронен
      // у всех участников, а не тикал локально вразнобой.
      final serverPos = pb.positionMs;
      if (serverPos != _positionMs) {
        setState(() => _positionMs = serverPos);
      }
    } else if (pb.isPlaying) {
      setState(() {
        // Вне сессии — прежнее плавное локальное наращивание.
        _positionMs = (_positionMs + 200).clamp(0, pb.durationMs);
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

  // Устойчивая сигнатура обложки: комбинирует uri трека и хеш содержимого
  // картинки (по сэмплам байтов — быстро, без полного прохода по мегабайтам).
  // uri в основе — чтобы смена трека всегда триггерила пересчёт, даже если
  // обложка побайтово идентична (треки одного альбома). Содержимое в хеше —
  // чтобы поймать позднюю догрузку картинки в рамках того же uri.
  int _imageSignature(Uint8List bytes, String? uri) {
    int hash = (uri?.hashCode ?? 0) ^ 0x9E3779B1;
    hash = 0x1fffffff & (hash + bytes.length);
    // Сэмплируем ~64 точки по всей длине — этого достаточно, чтобы различать
    // разные картинки, и дёшево даже для больших обложек.
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

  // ФИКС №3: Передаем trackUri, чтобы защититься от Race Condition
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

    // Ключ кэша: imageUrl если есть, иначе uri трека (на Android imageUrl
    // часто null — обложка приходит байтами, кэшировать по url нельзя).
    final String? cacheKey = imageUrl ?? trackUri;

    // Проверяем кэш
    if (cacheKey != null && provider.paletteCache.containsKey(cacheKey)) {
      final p = provider.paletteCache[cacheKey]!;
      _applyPalette(p, trackUri, provider);
      return;
    }

    try {
      final ImageProvider<Object> providerImg;
      if (imageBytes != null) {
        providerImg = MemoryImage(imageBytes);
      } else {
        providerImg = NetworkImage(imageUrl!);
      }

      final palette = await PaletteGenerator.fromImageProvider(
        providerImg,
        size: const Size(150, 150), // Чуть уменьшили размер для ускорения парсинга
        maximumColorCount: 12,
      );

      if (cacheKey != null) {
        provider.paletteCache[cacheKey] = palette;
      }

      if (!mounted) return;
      _applyPalette(palette, trackUri, provider);
    } catch (e) {
    }
  }

  // Применяет палитру напрямую. Раньше это было обёрнуто в
  // addPostFrameCallback + проверку uri, которая на Android при частых
  // обновлениях состояния плеера могла молча отменять валидный пересчёт.
  // Проверяем актуальность трека мягко: если uri уже сменился — просто
  // не применяем (следующий трек сам себя пересчитает).
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
    final theme = Theme.of(context);

    return Consumer<PlaybackProvider>(
      builder: (ctx, pb, _) {
        final title = pb.currentTrack?['title'] ?? widget.title ?? 'Unknown Title';
        final artist = pb.currentTrack?['artist'] ?? widget.artist ?? 'Unknown Artist';
        final duration = pb.durationMs;
        final imageBytes = pb.currentImageBytes;
        final imageUrl = pb.currentTrack?['imageUrl'] ?? widget.artworkUrl;
        final currentUri = pb.currentTrack?['uri'];

        if (!_dragging) {
          // Если секунда в провайдере изменилась (или трек переключился/применился seek)
          if (_lastSyncPosition != pb.positionMs) {
            _positionMs = pb.positionMs;       // Обновляем визуальную позицию
            _lastSyncPosition = pb.positionMs; // Запоминаем её
          }
        }

        // Отслеживаем смену трека чисто и без побочных эффектов
        if (currentUri != _lastTrackUri) {
          _lastTrackUri = currentUri;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            // ВАЖНО: берём картинку СВЕЖЕЙ из провайдера прямо здесь, а не из
            // imageBytes/imageUrl, захваченных в билде. При обычном (не-shuffle)
            // переключении трека uri в провайдере меняется раньше, чем
            // подгружаются новые байты обложки — поэтому захваченный imageBytes
            // мог быть ещё от предыдущего трека или null, и палитра не
            // обновлялась. В shuffle порядок обновления другой, там байты
            // успевали, поэтому фон менялся — отсюда "меняется только в перемешку".
            final freshBytes = pb.currentImageBytes;
            final freshUrl = pb.currentTrack?['imageUrl'] ?? widget.artworkUrl;

            // Ставим базовые нейтральные цвета на момент загрузки, если нет в кэше
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

        // Ловим ПОЗДНЮЮ загрузку обложки: uri мог смениться раньше, чем
        // подгрузились байты картинки (типичный случай при обычном
        // переключении трека на Android). Как только байты реально
        // появились/сменились — пересчитываем палитру.
        //
        // ВАЖНО: сигнатура — хеш СОДЕРЖИМОГО обложки, а не её длина. У треков
        // одного альбома (напр. несколько песен Skillet с одной обложкой
        // альбома, либо разные обложки одинакового размера) длина байтов
        // часто совпадает — из-за этого пересчёт по длине пропускался и фон
        // застревал. Плюс привязываем к uri: даже если у двух треков обложка
        // побайтово идентична, смена uri всё равно инициирует пересчёт.
        final int? imageSig =
            imageBytes != null ? _imageSignature(imageBytes, currentUri) : null;
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

        return Scaffold(
  body: Stack(
    fit: StackFit.expand,
    children: [
      _AnimatedGlowBackground(
        dominantColor: _displayDominant,
        vibrantColor: _displayVibrant,
      ),
      
      // ФИКС ЧИТАЕМОСТИ: Мягкое затемнение сверху и снизу
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.4), // Затемнение под заголовок
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55), // Затемнение под элементы управления
              ],
              stops: const [0.0, 0.25, 0.65, 1.0],
            ),
          ),
        ),
      ),
              SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          AppIconButton(
                            icon: Icons.keyboard_arrow_down_rounded,
                            size: 32,
                            color: Colors.white,
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
                    
                    // ФИКС №1: Красивый и надежный Cross-Fade обложек через AnimatedSwitcher
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 48),
                      height: MediaQuery.of(context).size.width * 0.58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _displayDominant.withOpacity(0.4),
                            blurRadius: 40,
                            spreadRadius: 5,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                          child: Container(
                          // ФИКС КЛЮЧА: теперь он уникален для каждой комбинации трека и его обложки
                          key: ValueKey<String>('${currentUri ?? 'empty'}_${imageBytes != null ? 'bytes' : imageUrl ?? 'no_url'}'),
                          width: double.infinity,
                          height: double.infinity,
                          child: imageBytes != null
                                ? Image.memory(imageBytes, fit: BoxFit.cover)
                                : imageUrl != null && imageUrl.isNotEmpty
                                    ? Image.network(imageUrl, fit: BoxFit.cover)
                                    : Container(
                                        color: Colors.white12,
                                        child: const Icon(Icons.music_note, size: 80, color: Colors.white38),
                                      ),
                          ),
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
                    
                    // ФИКС №2: Передаем состояние изменения ползунка onChanged
                    _NowPlayingProgressBar(
                      positionMs: _positionMs,
                      durationMs: duration,
                      activeColor: _displayVibrant,
                      onChanged: (ms) {
                        setState(() {
                          _dragging = true;
                          _positionMs = ms;
                        });
                      },
                      onSeek: (ms) {
                        setState(() {
                          _dragging = false;
                          _positionMs = ms;
                        });
                        pb.seekTo(ms);
                      },
                      formatMs: _formatMs,
                    ),
                    
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          AppIconButton(
                            icon: Icons.shuffle,
                            onPressed: () => pb.setShuffle(!pb.shuffleActive),
                            color: pb.shuffleActive ? _displayVibrant : Colors.white70,
                            size: 26,
                          ),
                          AppIconButton(
                            icon: Icons.skip_previous,
                            onPressed: () {
                              setState(() => _positionMs = 0);
                              pb.skipPrevious();
                            },
                            size: 36,
                            color: Colors.white,
                          ),
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _displayVibrant,
                            ),
                            child: AppIconButton(
                              icon: pb.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              onPressed: () => pb.togglePlay(),
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.skip_next,
                            onPressed: () {
                              setState(() => _positionMs = 0);
                              pb.skipNext();
                            },
                            size: 36,
                            color: Colors.white,
                          ),
                          AppIconButton(
                            icon: pb.repeatMode == 'track' ? Icons.repeat_one : Icons.repeat,
                            color: pb.repeatActive ? _displayVibrant : Colors.white70,
                            size: 26,
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

class _NowPlayingProgressBar extends StatelessWidget {
  final int positionMs;
  final int durationMs;
  final Color activeColor;
  final ValueChanged<int> onChanged; // Добавлено!
  final ValueChanged<int> onSeek;
  final String Function(int) formatMs;

  const _NowPlayingProgressBar({
    required this.positionMs,
    required this.durationMs,
    required this.activeColor,
    required this.onChanged,
    required this.onSeek,
    required this.formatMs,
  });

  @override
  Widget build(BuildContext context) {
    // Пример реализации на базе стандартного Slider (или твоего плагина):
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: activeColor,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              trackHeight: 4,
            ),
            child: Slider(
              value: positionMs.toDouble().clamp(0.0, durationMs.toDouble()),
              min: 0.0,
              max: durationMs.toDouble() == 0.0 ? 1.0 : durationMs.toDouble(),
              onChanged: (value) {
                onChanged(value.toInt()); // Сообщаем экрану, что мы начали тащить ползунок
              },
              onChangeEnd: (value) {
                onSeek(value.toInt()); // Пользователь отпустил палец, делаем seek в аудио-движке
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatMs(positionMs), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(formatMs(durationMs), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }
}