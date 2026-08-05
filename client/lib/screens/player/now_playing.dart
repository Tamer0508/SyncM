import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';
import '../../theme.dart';

/// Приглушённый свет на заднем плане плеера, окрашенный обложкой трека.
///
/// Заменяет прежний фон из сетки соединённых точек и слоя концентрических
/// кругов. Сетка узлов с линиями — приём настолько растиражированный, что
/// читается как оформление по умолчанию; вдобавок она перерисовывала полсотни
/// точек и связей между ними каждый кадр, а вместе с ней в том же CustomPaint
/// крутились два независимых контроллера анимации.
///
/// Здесь три пятна света, размытые по Гауссу и медленно смещающиеся. Цвета
/// приходят из палитры обложки, поэтому фон меняется вместе с треком.
class _AnimatedGlowBackground extends StatefulWidget {
  const _AnimatedGlowBackground({
    required this.dominantColor,
    required this.vibrantColor,
  });

  final Color dominantColor;
  final Color vibrantColor;

  @override
  State<_AnimatedGlowBackground> createState() => _AnimatedGlowBackgroundState();
}

class _AnimatedGlowBackgroundState extends State<_AnimatedGlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Один контроллер вместо двух: прежний фон крутил отдельные анимации для
    // частиц и для кругов, и обе перерисовывались независимо.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 48),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
            child: CustomPaint(
              painter: _GlowPainter(
                progress: _controller.value,
                dominant: widget.dominantColor,
                vibrant: widget.vibrantColor,
                // В тёмной теме свет заметнее из-за контраста с фоном,
                // поэтому яркость там ниже — иначе пятна выглядят как
                // подсветка, а не как рассеянный свет.
                opacity: isDark ? 0.30 : 0.38,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.progress,
    required this.dominant,
    required this.vibrant,
    required this.opacity,
  });

  final double progress;
  final Color dominant;
  final Color vibrant;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2 * math.pi;
    final shortest = size.shortestSide;

    void glow(Offset center, double radius, Color color) {
      canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: opacity));
    }

    // Периоды не кратны друг другу — картина не повторяется заметным циклом.
    glow(
      Offset(size.width * (0.22 + 0.12 * math.sin(t)),
          size.height * (0.20 + 0.07 * math.cos(t * 0.8))),
      shortest * 0.85,
      dominant,
    );
    glow(
      Offset(size.width * (0.82 + 0.10 * math.cos(t * 0.6)),
          size.height * (0.42 + 0.10 * math.sin(t * 0.9))),
      shortest * 0.70,
      vibrant,
    );
    glow(
      Offset(size.width * (0.50 + 0.14 * math.sin(t * 0.45 + 1.2)),
          size.height * (0.88 + 0.06 * math.cos(t * 0.7))),
      shortest * 0.75,
      dominant,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.progress != progress ||
      old.opacity != opacity ||
      old.dominant != dominant ||
      old.vibrant != vibrant;
}


class NowPlayingScreen extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? artworkUrl;

  const NowPlayingScreen({super.key, this.title, this.artist, this.artworkUrl});

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

  /// Номер текущего запроса палитры — для отбрасывания устаревших результатов.
  int _paletteRequest = 0;

  /// Сохранённая ссылка на провайдер для безопасного использования в dispose.
  PlaybackProvider? _playback;

  @override
  void initState() {
    super.initState();
    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    _playback = pb;
    _positionMs = pb.positionMs;

    // Сообщаем оболочке, что открыт полноэкранный плеер: мини-плеер внизу
    // должен уйти. Через postFrameCallback, потому что notifyListeners во
    // время построения дерева вызывает исключение.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pb.setFullScreenPlayerOpen(true);
    });
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
    // Снимаем флаг: мини-плеер внизу должен вернуться после закрытия.
    // Ссылка сохранена заранее: обращаться к Provider.of в dispose
    // ненадёжно — дерево уже разбирается, и поиск провайдера может не
    // удаться. Исключение при этом проглатывается, флаг остаётся поднятым,
    // и мини-плеер не показывается больше никогда.
    _playback?.setFullScreenPlayerOpen(false);
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

    final request = ++_paletteRequest;

    try {
      final ImageProvider<Object> providerImg;
      if (imageBytes != null) {
        providerImg = MemoryImage(imageBytes);
      } else {
        providerImg = NetworkImage(imageUrl!);
      }

      final palette = await PaletteGenerator.fromImageProvider(
        providerImg,
        // 64×64 и 8 цветов вместо 150×150 и 12.
        //
        // Квантование выполняется в основном потоке, и его стоимость растёт
        // пропорционально числу точек: 150×150 — это больше двадцати тысяч
        // пикселей, из-за которых фон заметно отставал от смены трека.
        // Для размытого свечения такая точность избыточна — доминирующий
        // цвет обложки при 64×64 практически тот же.
        size: const Size(64, 64),
        maximumColorCount: 8,
      );

      // Поздний результат от предыдущего трека отбрасываем: при быстром
      // переключении извлечения накладываются, и раньше побеждало то,
      // которое завершилось последним, — не обязательно актуальное.
      if (!mounted || request != _paletteRequest) return;

      if (cacheKey != null) {
        // Кэш ограничен: за долгую сессию он рос без предела, удерживая
        // палитры всех прослушанных обложек.
        if (provider.paletteCache.length > 60) {
          provider.paletteCache.remove(provider.paletteCache.keys.first);
        }
        provider.paletteCache[cacheKey] = palette;
      }

      _applyPalette(palette, trackUri, provider);
    } catch (err) {
      // Обложка недоступна или повреждена — остаёмся на текущих цветах.
      debugPrint('Palette extraction failed: $err');
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
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _AnimatedGlowBackground(
                dominantColor: _displayDominant,
                vibrantColor: _displayVibrant,
              ),

              // Затемнение сверху и снизу — под шапку и под управление.
              // Без него светлая обложка делает белый текст нечитаемым.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0x8C000000),
                      ],
                      stops: [0.0, 0.25, 0.6, 1.0],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Размер обложки считается от доступной ВЫСОТЫ, а не от
                    // ширины экрана. Раньше стояло width * 0.58: на низком
                    // окне (браузер, разделённый экран, открытая клавиатура)
                    // обложка не помещалась и содержимое переполняло экран.
                    final artSize = (constraints.maxHeight * 0.42)
                        .clamp(140.0, constraints.maxWidth - 96);

                    return Column(
                      children: [
                        _Header(onClose: () => Navigator.of(context).pop()),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _Artwork(
                                    size: artSize,
                                    glowColor: _displayDominant,
                                    imageBytes: imageBytes,
                                    imageUrl: imageUrl,
                                    trackKey: '$currentUri|${imageBytes?.length ?? 0}',
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _TrackInfo(title: title, artist: artist),
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
                              _NowPlayingProgressBar(
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
                              const SizedBox(height: AppSpacing.md),
                              _Controls(
                                isPlaying: pb.isPlaying,
                                accentColor: _displayVibrant,
                                onPrevious: pb.skipPrevious,
                                onNext: pb.skipNext,
                                onToggle: pb.togglePlay,
                                isShuffle: pb.shuffleActive,
                                repeatMode: pb.repeatMode,
                                onShuffle: () => pb.setShuffle(!pb.shuffleActive),
                                onRepeat: pb.cycleRepeatMode,
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
        );
      },
    );
  }

}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
              // Русская подпись вместо «NOW PLAYING»: это была одна из
              // немногих английских строк в интерфейсе.
              'Сейчас играет',
              textAlign: TextAlign.center,
              style: context.texts.labelLarge?.copyWith(
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
          // Пустая область той же ширины, что кнопка слева, — чтобы подпись
          // оставалась строго по центру.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.size,
    required this.glowColor,
    required this.imageBytes,
    required this.imageUrl,
    required this.trackKey,
  });

  final double size;
  final Color glowColor;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String trackKey;

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (imageBytes != null) {
      image = Image.memory(imageBytes!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      image = Image.network(imageUrl!, fit: BoxFit.cover);
    } else {
      image = ColoredBox(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Icon(Icons.music_note_rounded, size: 64, color: Colors.white54),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.large,
          boxShadow: [
            // Свечение цветом обложки под ней самой — приём, который делает
            // изображение «источником света» на экране.
            BoxShadow(
              color: glowColor.withValues(alpha: 0.45),
              blurRadius: 48,
              spreadRadius: 4,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.large,
          child: AnimatedSwitcher(
            duration: AppMotion.long,
            switchInCurve: AppMotion.emphasizedDecelerate,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              // Лёгкое увеличение при появлении: смена обложки читается как
              // движение, а не как подмена картинки.
              child: ScaleTransition(
                scale: Tween<double>(begin: 1.04, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: SizedBox(key: ValueKey(trackKey), child: image),
          ),
        ),
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
            // headlineMedium вместо titleLarge: на экране плеера название
            // трека — главное, и крупная типографика здесь уместна.
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
      // Промежутки распределяет spaceEvenly. Отдельные SizedBox между
      // кнопками убраны: вместе они давали суммарную ширину больше
      // доступной, и ряд переполнялся на узком экране
      // («RenderFlex overflowed on the right»).
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Перемешивание и повтор — второстепенные режимы: меньше размером и
        // подсвечиваются только когда включены.
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
        // Главная кнопка — крупная и залитая акцентным цветом обложки.
        // Раньше все три кнопки были одинаковыми иконками, и центральная
        // ничем не выделялась, хотя нажимают её чаще остальных.
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
                scale: CurvedAnimation(parent: animation, curve: AppMotion.spring),
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
          // Три состояния: выключен, повтор списка, повтор одного трека.
          // Иконка меняется на repeat_one — по одному лишь цвету отличить
          // повтор списка от повтора трека невозможно.
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
      // Белый при включённом режиме, приглушённый при выключенном: акцентный
      // цвет обложки бывает тёмным и на затемнённом фоне терялся бы.
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
                style: context.texts.bodySmall?.copyWith(
                  color: Colors.white70,
                  // Моноширинные цифры: иначе левая метка дёргается по
                  // ширине на каждой секунде и «толкает» полосу.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _format(durationMs),
                style: context.texts.bodySmall?.copyWith(
                  color: Colors.white70,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}