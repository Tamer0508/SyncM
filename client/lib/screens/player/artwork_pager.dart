import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../theme.dart';
import '../../utils/image_cache.dart';

@immutable
class ArtworkSource {
  const ArtworkSource({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;

  bool get isEmpty => bytes == null && (url == null || url!.isEmpty);

  /// Длина Uint8List не уникальна (две разные обложки легко совпадают по
  /// размеру), поэтому идентичностью байтов служит сам объект буфера.
  Object get identity => url ?? bytes ?? _emptyIdentity;

  static const Object _emptyIdentity = 'artwork:empty';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkSource &&
          other.url == url &&
          identical(other.bytes, bytes);

  @override
  int get hashCode =>
      Object.hash(url, bytes == null ? null : identityHashCode(bytes));
}

class ArtworkPager extends StatefulWidget {
  const ArtworkPager({
    super.key,
    required this.size,
    required this.current,
    required this.previous,
    required this.next,
    required this.currentKey,
    required this.onNext,
    required this.onPrevious,
    required this.progress,
  });

  final double size;

  final ArtworkSource current;
  final ArtworkSource? previous;
  final ArtworkSource? next;

  final String currentKey;

  final VoidCallback onNext;
  final VoidCallback onPrevious;

  final ValueNotifier<double> progress;

  @override
  ArtworkPagerState createState() => ArtworkPagerState();
}

class ArtworkPagerState extends State<ArtworkPager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double _width = 1;

  int _settleTarget = 0;

  /// Каждый новый жест/settle получает свой номер. Completion-callback старой
  /// (остановленной) анимации обязан его проверить: whenCompleteOrCancel
  /// срабатывает и при stop(), иначе отменённый spring переключит трек.
  int _settleGeneration = 0;

  // Готовые плитки обложек. Пересобираются только при смене источника или
  // размера, поэтому кадр анимации меняет исключительно transform, а
  // ImageProvider и Image-виджеты остаются теми же объектами.
  double _tileSize = -1;
  ArtworkSource? _currentSource;
  ArtworkSource? _previousSource;
  ArtworkSource? _nextSource;
  Widget? _currentTile;
  Widget? _previousTile;
  Widget? _nextTile;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 0)
      ..addListener(() => widget.progress.value = _controller.value);
  }

  @override
  void didUpdateWidget(ArtworkPager old) {
    super.didUpdateWidget(old);

    if (widget.currentKey != old.currentKey) {
      // Трек уже сменился: незавершённый spring не имеет права вызвать
      // onNext/onPrevious ещё раз.
      _settleGeneration++;
      _settleTarget = 0;
      _controller.stop();
      _controller.value = 0;
      widget.progress.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    // Новый жест обесценивает предыдущий settle.
    _settleGeneration++;
    _settleTarget = 0;
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    var next = _controller.value - details.delta.dx / _width;

    if (next > 0 && widget.next == null) next = 0;
    if (next < 0 && widget.previous == null) next = 0;

    _controller.value = next.clamp(-1.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final value = _controller.value;

    const distanceThreshold = 0.28;
    const velocityThreshold = 600.0;

    var target = 0;
    if (value > distanceThreshold || velocity < -velocityThreshold) {
      if (widget.next != null) target = 1;
    } else if (value < -distanceThreshold || velocity > velocityThreshold) {
      if (widget.previous != null) target = -1;
    }

    _settleTo(target, velocity: velocity);
  }

  void _settleTo(int target, {double velocity = 0}) {
    final generation = ++_settleGeneration;
    _settleTarget = target;

    if (context.reduceMotion) {
      _controller.value = target.toDouble();
      _commitSettle(target, generation);
      return;
    }

    final simulation = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 320, damping: 32),
      _controller.value,
      target.toDouble(),
      -velocity / _width,
    );

    _controller
        .animateWith(simulation)
        .whenCompleteOrCancel(() => _commitSettle(target, generation));
  }

  void _commitSettle(int target, int generation) {
    if (!mounted || generation != _settleGeneration || _settleTarget != target) {
      return;
    }
    if (target == 1) {
      widget.onNext();
    } else if (target == -1) {
      widget.onPrevious();
    }
  }

  bool animateTo(int direction) {
    if (direction > 0 && widget.next == null) return false;
    if (direction < 0 && widget.previous == null) return false;
    _settleTo(direction);
    return true;
  }

  void _syncTiles() {
    final sizeChanged = widget.size != _tileSize;
    if (sizeChanged) _tileSize = widget.size;

    if (sizeChanged || _currentSource != widget.current) {
      _currentSource = widget.current;
      _currentTile = _buildTile(widget.current);
    }

    final previous = widget.previous;
    if (sizeChanged || _previousSource != previous) {
      _previousSource = previous;
      _previousTile = previous == null ? null : _buildTile(previous);
    }

    final next = widget.next;
    if (sizeChanged || _nextSource != next) {
      _nextSource = next;
      _nextTile = next == null ? null : _buildTile(next);
    }
  }

  Widget _buildTile(ArtworkSource source) => Center(
        child: _ArtworkTile(size: widget.size, source: source),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        _syncTiles();

        final previous = _previousTile;
        final current = _currentTile!;
        final next = _nextTile;

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;

              // Дети между кадрами — те же самые объекты, поэтому Flutter не
              // перестраивает поддеревья обложек: меняется только сдвиг.
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (previous != null) _slide(-1 - t, previous),
                  _slide(-t, current),
                  if (next != null) _slide(1 - t, next),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _slide(double offset, Widget tile) {
    return FractionalTranslation(
      translation: Offset(offset, 0),
      child: tile,
    );
  }
}

class _ArtworkTile extends StatelessWidget {
  const _ArtworkTile({required this.size, required this.source});

  final double size;
  final ArtworkSource source;

  @override
  Widget build(BuildContext context) {
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();

    Widget image;
    if (source.url != null && source.url!.isNotEmpty) {
      image = AppNetworkImage(url: source.url!, width: size, height: size);
    } else if (source.bytes != null) {
      image = Image.memory(
        source.bytes!,
        fit: BoxFit.cover,
        cacheWidth: decodeSize,
        gaplessPlayback: true,
      );
    } else {
      image = ColoredBox(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Icon(Icons.music_note_rounded, size: 64, color: Colors.white54),
      );
    }

    // Обложка живёт в собственном слое: при свайпе меняется только его
    // положение, готовый растр не перерисовывается заново каждый кадр.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: AppRadius.large,
        child: SizedBox(width: size, height: size, child: image),
      ),
    );
  }
}
