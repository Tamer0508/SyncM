import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sync_phase.dart';
import '../theme.dart';

/// Фирменный знак SyncM: два круга, «мой» и «его».
///
/// Это единственное место, где приложение позволяет себе быть громким —
/// поэтому всё вокруг него держится тихо.
///
/// Знак не украшение: он говорит то же, ради чего написана вся синхронизация
/// в providers/playback_provider.dart. Врозь — никто ничего не слушает вместе.
/// Пересеклись и пересечение засветилось — звучит одно и то же в одну и ту же
/// секунду. Разошлись — расхождение, идёт подстройка. Человек читает состояние
/// сессии, не читая ни слова.
///
/// Цвета закреплены за ролями по всему приложению (roles.mine / roles.theirs),
/// так что знак заодно учит их различать.
class SyncMark extends StatefulWidget {
  const SyncMark({
    super.key,
    this.state = SyncPhase.idle,
    this.size = 96,
  });

  final SyncPhase state;

  /// Ширина знака целиком. Диаметр круга — примерно 55% от неё.
  final double size;

  @override
  State<SyncMark> createState() => _SyncMarkState();
}

class _SyncMarkState extends State<SyncMark> with TickerProviderStateMixin {
  /// Переход между состояниями. Отдельный контроллер, потому что смена
  /// состояния — событие, а не фон.
  late final AnimationController _transition;

  /// Медленное дыхание. Идёт только там, где что-то происходит, — в покое
  /// остановлен: постоянное движение на экране, куда заходят по десять раз в
  /// день, утомляет и жрёт батарею.
  late final AnimationController _ambient;

  double _from = 0;
  double _to = 0;

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(vsync: this, duration: AppMotion.page);
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _from = _to = _overlapFor(widget.state);
    _transition.value = 1;
    _syncAmbient();
  }

  @override
  void didUpdateWidget(SyncMark old) {
    super.didUpdateWidget(old);
    if (old.state == widget.state) return;

    // Стартуем не от целевого значения предыдущего состояния, а от того, где
    // круги сейчас: состояние может смениться посреди перехода, и прыжок был
    // бы виден.
    _from = _currentOverlap;
    _to = _overlapFor(widget.state);
    _transition.forward(from: 0);
    _syncAmbient();
  }

  void _syncAmbient() {
    final wants = widget.state == SyncPhase.waiting ||
        widget.state == SyncPhase.synced ||
        widget.state == SyncPhase.drifting;

    if (wants && !_ambient.isAnimating) {
      _ambient.repeat(reverse: true);
    } else if (!wants && _ambient.isAnimating) {
      _ambient.stop();
      _ambient.value = 0;
    }
  }

  /// Насколько круги перекрываются: 0 — касаются краями, 1 — совпали.
  static double _overlapFor(SyncPhase state) => switch (state) {
        SyncPhase.idle => 0.0,
        SyncPhase.waiting => 0.18,
        SyncPhase.synced => 0.55,
        SyncPhase.drifting => 0.3,
      };

  double get _currentOverlap {
    final t = Curves.easeOutCubic.transform(_transition.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _transition.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roles = context.roles;
    final still = context.reduceMotion;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size * 0.58,
        child: AnimatedBuilder(
          animation: Listenable.merge([_transition, _ambient]),
          builder: (context, _) {
            // При «меньше движения» знак остаётся информативным: положение
            // кругов по-прежнему отражает состояние, но не дышит и не едет.
            final overlap = still ? _to : _currentOverlap;

            var breath = 0.0;
            if (!still) {
              final wave = math.sin(_ambient.value * math.pi);
              breath = switch (widget.state) {
                // В синхроне — общее, ровное дыхание: круги движутся заодно.
                SyncPhase.synced => wave * 0.045,
                // В ожидании — короткие подходы друг к другу.
                SyncPhase.waiting => wave * 0.09,
                // При расхождении — качание в противофазе, круги «не попадают».
                SyncPhase.drifting => -wave * 0.11,
                SyncPhase.idle => 0.0,
              };
            }

            return CustomPaint(
              painter: _SyncMarkPainter(
                overlap: (overlap + breath).clamp(-0.05, 0.72),
                mine: roles.mine,
                theirs: roles.theirs,
                lit: widget.state == SyncPhase.synced,
                dimmed: widget.state == SyncPhase.idle,
                antiPhase: widget.state == SyncPhase.drifting,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SyncMarkPainter extends CustomPainter {
  _SyncMarkPainter({
    required this.overlap,
    required this.mine,
    required this.theirs,
    required this.lit,
    required this.dimmed,
    required this.antiPhase,
  });

  final double overlap;
  final Color mine;
  final Color theirs;
  final bool lit;
  final bool dimmed;
  final bool antiPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height / 2;
    final centerY = size.height / 2;

    // При overlap = 0 круги касаются краями, при 1 — центры совпадают.
    final gap = radius * (1 - overlap);

    final leftCenter = Offset(size.width / 2 - gap, centerY);
    final rightCenter = Offset(size.width / 2 + gap, centerY);

    final alpha = dimmed ? 0.55 : 0.92;

    final leftPaint = Paint()..color = mine.withValues(alpha: alpha);
    final rightPaint = Paint()..color = theirs.withValues(alpha: alpha);

    canvas.drawCircle(leftCenter, radius, leftPaint);
    canvas.drawCircle(rightCenter, radius, rightPaint);

    if (!lit || overlap <= 0) return;

    // Пересечение — та самая «одна и та же секунда». Рисуем его отдельным
    // светлым слоем через пересечение двух окружностей: это единственная
    // часть знака, которая существует, только когда сессия действительно
    // синхронна.
    final left = Path()
      ..addOval(Rect.fromCircle(center: leftCenter, radius: radius));
    final right = Path()
      ..addOval(Rect.fromCircle(center: rightCenter, radius: radius));
    final lens = Path.combine(PathOperation.intersect, left, right);

    final blend = Color.lerp(mine, theirs, 0.5)!;
    canvas.drawPath(
      lens,
      Paint()
        ..color = Color.lerp(blend, Colors.white, 0.55)!.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_SyncMarkPainter old) =>
      old.overlap != overlap ||
      old.mine != mine ||
      old.theirs != theirs ||
      old.lit != lit ||
      old.dimmed != dimmed ||
      old.antiPhase != antiPhase;
}