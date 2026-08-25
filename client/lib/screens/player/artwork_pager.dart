import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

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

@immutable
class ArtworkSlot {
  const ArtworkSlot({required this.trackId, required this.source});

  final String trackId;
  final ArtworkSource source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkSlot &&
          other.trackId == trackId &&
          other.source == source;

  @override
  int get hashCode => Object.hash(trackId, source);
}

class ArtworkPager extends StatefulWidget {
  const ArtworkPager({
    super.key,
    required this.size,
    required this.current,
    required this.previous,
    required this.next,
    required this.switching,
    required this.onNext,
    required this.onPrevious,
    required this.progress,
  });

  final double size;

  final ArtworkSlot current;
  final ArtworkSlot? previous;
  final ArtworkSlot? next;

  final bool switching;

  final bool Function() onNext;
  final bool Function() onPrevious;

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
  ArtworkSlot? _currentSlot;
  ArtworkSlot? _previousSlot;
  ArtworkSlot? _nextSlot;
  Widget? _currentTile;
  Widget? _previousTile;
  Widget? _nextTile;

  Key _currentTileKey = const ValueKey<String>('artwork.slot.1');
  Key _previousTileKey = const ValueKey<String>('artwork.slot.0');
  Key _nextTileKey = const ValueKey<String>('artwork.slot.2');

  /// Трек, на который пользователь уже свайпнул и чья плитка стоит в центре,
  /// пока провайдер не подтвердил смену. Пока значение не `null`, пружина
  /// удерживается в закоммиченной точке.
  String? _pendingTrackId;

  bool get _isCommitting => _pendingTrackId != null;

  bool _progressFlushScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this, value: 0)
      ..addListener(_publishProgress);
  }

  void _publishProgress() {
    final value = _controller.value;
    if (widget.progress.value == value) return;

    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      widget.progress.value = value;
      return;
    }

    if (_progressFlushScheduled) return;
    _progressFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _progressFlushScheduled = false;
      if (!mounted) return;
      widget.progress.value = _controller.value;
    });
  }

  @override
  void didUpdateWidget(ArtworkPager oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isCommitting) {
      final confirmed = widget.current.trackId == _pendingTrackId;

      if (confirmed || !widget.switching) _resetToCurrent();
      return;
    }

    if (widget.current.trackId != oldWidget.current.trackId) {
      _resetToCurrent();
    }
  }

  void _resetToCurrent() {
    _pendingTrackId = null;
    _settleGeneration++;
    _settleTarget = 0;
    _controller.stop();
    _controller.value = 0;
    _publishProgress();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    if (_isCommitting) return;

    // Новый жест обесценивает предыдущий settle.
    _settleGeneration++;
    _settleTarget = 0;
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isCommitting) return;

    var next = _controller.value - details.delta.dx / _width;

    if (next > 0 && widget.next == null) next = 0;
    if (next < 0 && widget.previous == null) next = 0;

    _controller.value = next.clamp(-1.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isCommitting) return;

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
    if (target == 0) return;

    final committed = target == 1 ? widget.next : widget.previous;
    final accepted = committed != null &&
        (target == 1 ? widget.onNext() : widget.onPrevious());

    if (!accepted || committed.trackId == widget.current.trackId) {
      _resetToCurrent();
      return;
    }

    _pendingTrackId = committed.trackId;
    _controller.stop();
    _controller.value = target.toDouble();
    _publishProgress();
  }

  bool animateTo(int direction) {
    if (_isCommitting) return true;

    if (direction > 0 && widget.next == null) return false;
    if (direction < 0 && widget.previous == null) return false;
    _settleTo(direction);
    return true;
  }

  void _syncTiles() {
    final sizeChanged = widget.size != _tileSize;
    if (sizeChanged) _tileSize = widget.size;

    if (sizeChanged || _currentSlot != widget.current) {
      _currentSlot = widget.current;
      _currentTile = _buildTile(widget.current);
    }

    final previous = widget.previous;
    if (sizeChanged || _previousSlot != previous) {
      _previousSlot = previous;
      _previousTile = previous == null ? null : _buildTile(previous);
    }

    final next = widget.next;
    if (sizeChanged || _nextSlot != next) {
      _nextSlot = next;
      _nextTile = next == null ? null : _buildTile(next);
    }

    _syncKeys();
  }

  void _syncKeys() {
    final seen = <String>{};
    _currentTileKey = _tileKey(widget.current.trackId, 1, seen);
    _nextTileKey = _tileKey(widget.next?.trackId, 2, seen);
    _previousTileKey = _tileKey(widget.previous?.trackId, 0, seen);
  }

  static Key _tileKey(String? trackId, int slot, Set<String> seen) =>
      trackId != null && trackId.isNotEmpty && seen.add(trackId)
          ? ValueKey<String>('artwork.track.$trackId')
          : ValueKey<String>('artwork.slot.$slot');

  Widget _buildTile(ArtworkSlot slot) => Center(
        child: _ArtworkTile(size: widget.size, source: slot.source),
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
          behavior: HitTestBehavior.opaque,
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
                  if (previous != null)
                    _slide(-1 - t, previous, _previousTileKey),
                  _slide(-t, current, _currentTileKey),
                  if (next != null) _slide(1 - t, next, _nextTileKey),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _slide(double offset, Widget tile, Key key) {
    return FractionalTranslation(
      key: key,
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
        color: context.colors.onSurface.withValues(alpha: 0.08),
        child: Icon(
          Icons.music_note_rounded,
          size: 64,
          color: context.colors.onSurfaceVariant,
        ),
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
