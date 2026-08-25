import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Мерцание поверх заглушек.
///
/// Один контроллер на весь список, а не на строку: анимация здесь —
/// исключительно окраска, она ничего не двигает и не меняет размеров.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Skeleton old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    if (context.reduceMotion) return widget.child;

    final highlight = context.colors.onSurface.withValues(alpha: 0.07);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final slide = _controller.value * 2 - 0.5;
          return ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  highlight,
                  Colors.transparent,
                ],
                stops: [
                  (slide - 0.25).clamp(0.0, 1.0),
                  slide.clamp(0.0, 1.0),
                  (slide + 0.25).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.circle = false,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius:
            circle ? null : (borderRadius ?? BorderRadius.circular(AppRadius.xs)),
      ),
    );
  }
}

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.style,
    this.width,
    this.widthFactor = 1.0,
    this.thickness,
  });

  final TextStyle? style;

  final double? width;

  final double widthFactor;

  final double? thickness;

  @override
  Widget build(BuildContext context) {
    final resolved = style ?? DefaultTextStyle.of(context).style;

    Widget bar = SkeletonBox(
      width: width,
      height: thickness ?? (resolved.fontSize ?? 14),
    );

    if (width == null) {
      bar = FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: bar,
      );
    }

    return SizedBox(
      width: width ?? double.infinity,
      child: Stack(
        children: [
          Text('​', style: resolved, maxLines: 1, softWrap: false),
          Positioned.fill(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: bar,
            ),
          ),
        ],
      ),
    );
  }
}

class SkeletonSlot extends StatelessWidget {
  const SkeletonSlot({
    super.key,
    required this.reserve,
    this.child,
    this.fill = false,
  });

  final Widget reserve;
  final Widget? child;

  final bool fill;

  @override
  Widget build(BuildContext context) {
    final mark = child;

    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: IgnorePointer(
            child: Opacity(opacity: 0, child: reserve),
          ),
        ),
        if (mark != null)
          if (fill) Positioned.fill(child: mark) else mark,
      ],
    );
  }
}

class SkeletonIcon extends StatelessWidget {
  const SkeletonIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(width: size, height: size, circle: true);
  }
}

double _labelWidth(BuildContext context, String label, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();

  return painter.width;
}

const List<double> _titleFactors = [0.54, 0.38, 0.64, 0.46, 0.58];
const List<double> _subtitleFactors = [0.32, 0.24, 0.40, 0.28, 0.35];

double _titleFactor(int i) => _titleFactors[i % _titleFactors.length];
double _subtitleFactor(int i) => _subtitleFactors[i % _subtitleFactors.length];

class SkeletonListFrame extends StatelessWidget {
  const SkeletonListFrame({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.padding,
    required this.spacing,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  final EdgeInsetsGeometry padding;

  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, _) => SizedBox(height: spacing),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.padding,
    required this.leading,
    required this.gap,
    required this.lines,
    required this.lineGap,
    this.trailing,
    this.decoration,
  });

  final EdgeInsetsGeometry padding;
  final Widget leading;
  final double gap;
  final List<Widget> lines;
  final double lineGap;
  final Widget? trailing;
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final end = trailing;

    return Container(
      padding: padding,
      decoration: decoration,
      child: Row(
        children: [
          leading,
          SizedBox(width: gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) SizedBox(height: lineGap),
                  lines[i],
                ],
              ],
            ),
          ),
          if (end != null) end,
        ],
      ),
    );
  }
}


class SkeletonFriendTile extends StatelessWidget {
  const SkeletonFriendTile({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return _SkeletonRow(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 2,
      ),
      // TappableAvatar(radius: 21).
      leading: const SkeletonBox(width: 42, height: 42, circle: true),
      gap: AppSpacing.sm + 4,
      lineGap: 2,
      lines: [
        SkeletonLine(style: texts.titleMedium, widthFactor: _titleFactor(index)),
        SkeletonLine(style: texts.bodySmall, widthFactor: _subtitleFactor(index)),
      ],
      trailing: const SkeletonSlot(
        reserve: IconButton(
          onPressed: null,
          icon: Icon(Icons.more_vert_rounded),
        ),
        child: SkeletonIcon(),
      ),
    );
  }
}

class SkeletonFriendList extends StatelessWidget {
  const SkeletonFriendList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      spacing: 3,
      itemBuilder: (_, i) => SkeletonFriendTile(index: i),
    );
  }
}


class SkeletonRequestCard extends StatelessWidget {
  const SkeletonRequestCard({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return _SkeletonRow(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.row),
      ),
      leading: const SkeletonBox(width: 42, height: 42, circle: true),
      gap: AppSpacing.sm + 4,
      lineGap: 2,
      lines: [
        SkeletonLine(style: texts.titleMedium, widthFactor: _titleFactor(index)),
        SkeletonLine(style: texts.bodySmall, widthFactor: _subtitleFactor(index)),
      ],
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: AppSpacing.sm),
          SkeletonSlot(
            reserve: IconButton(
              onPressed: null,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 22),
            ),
            child: SkeletonIcon(size: 22),
          ),
          SkeletonSlot(
            reserve: IconButton(
              onPressed: null,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.check_rounded, size: 22),
            ),
            child: SkeletonIcon(size: 22),
          ),
        ],
      ),
    );
  }
}

class SkeletonRequestList extends StatelessWidget {
  const SkeletonRequestList({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      spacing: 3,
      itemBuilder: (_, i) => SkeletonRequestCard(index: i),
    );
  }
}


class SkeletonInviteCard extends StatelessWidget {
  const SkeletonInviteCard({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final l = L.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: AppRadius.large,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 44, height: 44, borderRadius: AppRadius.small),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SkeletonLine(
                      style: texts.titleMedium,
                      widthFactor: _titleFactor(index),
                    ),
                    const SizedBox(height: 2),
                    SkeletonLine(
                      style: texts.bodySmall,
                      widthFactor: _subtitleFactor(index),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          Row(
            children: [
              const SkeletonIcon(size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SkeletonLine(style: texts.bodySmall, widthFactor: 0.22),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: SkeletonSlot(
                  fill: true,
                  reserve: OutlinedButton(
                    onPressed: null,
                    child: Text(l.requestsDecline),
                  ),
                  child: SkeletonBox(
                    height: AppSizes.buttonHeightDense,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: SkeletonSlot(
                  fill: true,
                  reserve: FilledButton(
                    onPressed: null,
                    child: Text(l.requestsAccept),
                  ),
                  child: SkeletonBox(
                    height: AppSizes.buttonHeight,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SkeletonInviteList extends StatelessWidget {
  const SkeletonInviteList({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.sm + 4,
      itemBuilder: (_, i) => SkeletonInviteCard(index: i),
    );
  }
}


class SkeletonBlockedList extends StatelessWidget {
  const SkeletonBlockedList({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final label = L.of(context).blockedUnblock;

    return SkeletonListFrame(
      itemCount: itemCount + 1,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.sm,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SkeletonLine(style: texts.bodySmall, widthFactor: 0.8),
          );
        }

        return _SkeletonRow(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: AppRadius.large,
          ),
          // TappableAvatar(radius: 22).
          leading: const SkeletonBox(width: 44, height: 44, circle: true),
          gap: AppSpacing.md,
          lineGap: 0,
          lines: [
            SkeletonLine(
              style: texts.titleSmall,
              widthFactor: _titleFactor(i - 1),
            ),
          ],
          trailing: SkeletonSlot(
            reserve: TextButton(onPressed: null, child: Text(label)),
            child: SkeletonLine(
              style: texts.labelLarge,
              width: _labelWidth(context, label, texts.labelLarge),
            ),
          ),
        );
      },
    );
  }
}


class SkeletonDeviceList extends StatelessWidget {
  const SkeletonDeviceList({super.key, this.itemCount = 3});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final label = L.of(context).commonFinish;

    return SkeletonListFrame(
      itemCount: itemCount + 1,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.sm,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SkeletonLine(style: texts.bodySmall, widthFactor: 0.75),
          );
        }

        return _SkeletonRow(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: AppRadius.large,
          ),
          leading: const SkeletonIcon(),
          gap: AppSpacing.md,
          lineGap: 2,
          lines: [
            SkeletonLine(
              style: texts.titleSmall,
              widthFactor: _titleFactor(i - 1),
            ),
            SkeletonLine(
              style: texts.bodySmall,
              widthFactor: _subtitleFactor(i - 1),
            ),
          ],
          trailing: SkeletonSlot(
            reserve: TextButton(onPressed: null, child: Text(label)),
            child: SkeletonLine(
              style: texts.labelLarge,
              width: _labelWidth(context, label, texts.labelLarge),
            ),
          ),
        );
      },
    );
  }
}

enum SkeletonTrackTrailing {
  /// Ничего.
  none,

  checkbox,

  box,

  menu,

  menuAndHandle,
}

class SkeletonTrackCard extends StatelessWidget {
  const SkeletonTrackCard({
    super.key,
    this.index = 0,
    this.showLike = false,
    this.showDuration = true,
    this.trailing = SkeletonTrackTrailing.none,
  });

  final int index;
  final bool showLike;
  final bool showDuration;
  final SkeletonTrackTrailing trailing;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final timecode = context.timecode();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SkeletonBox(width: 48, height: 48, borderRadius: AppRadius.small),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(
                  style: texts.titleSmall,
                  widthFactor: _titleFactor(index),
                ),
                const SizedBox(height: 2),
                SkeletonLine(
                  style: texts.bodySmall,
                  widthFactor: _subtitleFactor(index),
                ),
              ],
            ),
          ),
          if (showDuration) ...[
            const SizedBox(width: AppSpacing.sm),
            SkeletonLine(
              style: timecode,
              width: _labelWidth(context, '0:00', timecode),
            ),
          ],
          if (showLike) ...[
            const SizedBox(width: AppSpacing.xs),
            const SkeletonSlot(
              reserve: IconButton(
                onPressed: null,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.favorite_border_rounded, size: 20),
              ),
              child: SkeletonIcon(size: 20),
            ),
          ],
          ...switch (trailing) {
            SkeletonTrackTrailing.none => const <Widget>[],
            SkeletonTrackTrailing.checkbox => const <Widget>[
                SkeletonSlot(
                  reserve: Checkbox(value: false, onChanged: null),
                  child: SkeletonBox(width: 18, height: 18),
                ),
              ],
            SkeletonTrackTrailing.box => const <Widget>[
                SizedBox.square(
                  dimension: 48,
                  child: Center(child: SkeletonIcon()),
                ),
              ],
            SkeletonTrackTrailing.menu => const <Widget>[_SkeletonTrackMenu()],
            SkeletonTrackTrailing.menuAndHandle => const <Widget>[
                _SkeletonTrackMenu(),
                Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: SkeletonIcon(size: 20),
                ),
              ],
          },
        ],
      ),
    );
  }
}

class _SkeletonTrackMenu extends StatelessWidget {
  const _SkeletonTrackMenu();

  @override
  Widget build(BuildContext context) {
    return const SkeletonSlot(
      reserve: IconButton(
        onPressed: null,
        icon: Icon(Icons.more_vert_rounded),
      ),
      child: SkeletonIcon(),
    );
  }
}

class SkeletonTrackList extends StatelessWidget {
  const SkeletonTrackList({
    super.key,
    this.itemCount = 8,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.sm,
      AppSpacing.md,
    ),
    this.spacing = AppSpacing.xs,
    this.showLike = false,
    this.trailing = SkeletonTrackTrailing.none,
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final bool showLike;
  final SkeletonTrackTrailing trailing;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: padding,
      spacing: spacing,
      itemBuilder: (_, i) => SkeletonTrackCard(
        index: i,
        showLike: showLike,
        trailing: trailing,
      ),
    );
  }
}

class SkeletonHistoryList extends StatelessWidget {
  const SkeletonHistoryList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.xs,
      itemBuilder: (context, i) => ListTile(
        leading: SkeletonBox(
          width: 44,
          height: 44,
          borderRadius: AppRadius.small,
        ),
        title: SkeletonLine(widthFactor: _titleFactor(i)),
        subtitle: SkeletonLine(widthFactor: _subtitleFactor(i)),
        trailing: SkeletonLine(
          style: context.texts.bodySmall,
          width: _labelWidth(context, '00:00', context.texts.bodySmall),
        ),
      ),
    );
  }
}

class SkeletonPlaylistTile extends StatelessWidget {
  const SkeletonPlaylistTile({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return _SkeletonRow(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      leading: SkeletonBox(width: 52, height: 52, borderRadius: AppRadius.small),
      gap: AppSpacing.md,
      lineGap: 2,
      lines: [
        SkeletonLine(style: texts.titleSmall, widthFactor: _titleFactor(index)),
        SkeletonLine(style: texts.bodySmall, widthFactor: _subtitleFactor(index)),
      ],
      // На месте PlaylistActionsButton.
      trailing: const SkeletonSlot(
        reserve: IconButton(
          onPressed: null,
          icon: Icon(Icons.more_vert_rounded),
        ),
        child: SkeletonIcon(),
      ),
    );
  }
}

class SkeletonPlaylistList extends StatelessWidget {
  const SkeletonPlaylistList({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.xs,
      itemBuilder: (_, i) => SkeletonPlaylistTile(index: i),
    );
  }
}

/// Зеркало `_PlaylistTile` из выбора плейлиста для сессии.
class SkeletonPickPlaylistList extends StatelessWidget {
  const SkeletonPickPlaylistList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return SkeletonListFrame(
      itemCount: itemCount,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      spacing: AppSpacing.sm,
      itemBuilder: (context, i) => _SkeletonRow(
        padding: const EdgeInsets.all(AppSpacing.sm + 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: AppRadius.large,
        ),
        leading:
            SkeletonBox(width: 52, height: 52, borderRadius: AppRadius.small),
        gap: AppSpacing.md,
        lineGap: 2,
        lines: [
          SkeletonLine(style: texts.titleMedium, widthFactor: _titleFactor(i)),
          SkeletonLine(style: texts.bodySmall, widthFactor: _subtitleFactor(i)),
        ],
        // На месте шеврона.
        trailing: const SkeletonIcon(),
      ),
    );
  }
}


class SkeletonSessionCard extends StatelessWidget {
  const SkeletonSessionCard({super.key});

  static const double markWidth = 96;
  static const double markHeight = markWidth * 0.58;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;
    final l = L.of(context);

    return Skeleton(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: AppRadius.large,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _SkeletonSyncMark()),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.62,
                child: SkeletonLine(style: texts.titleLarge),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.86,
                child: SkeletonLine(style: texts.bodyMedium),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: SkeletonSlot(
                fill: true,
                reserve: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l.homeStartSession),
                ),
                child: SkeletonBox(
                  height: AppSizes.buttonHeight,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonSyncMark extends StatelessWidget {
  const _SkeletonSyncMark();

  @override
  Widget build(BuildContext context) {
    const width = SkeletonSessionCard.markWidth;
    const height = SkeletonSessionCard.markHeight;
    const radius = height / 2;

    return const SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: width / 2 - radius * 2,
            child: SkeletonBox(width: height, height: height, circle: true),
          ),
          Positioned(
            left: width / 2,
            child: SkeletonBox(width: height, height: height, circle: true),
          ),
        ],
      ),
    );
  }
}


/// Зеркало `_Hero`.
class SkeletonProfileHeader extends StatelessWidget {
  const SkeletonProfileHeader({super.key});

  static const double _narrowWidth = 700;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < _narrowWidth;
        final avatarSize = isNarrow ? 96.0 : 200.0;
        final nameSize = isNarrow ? 30.0 : 72.0;

        return Skeleton(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              isNarrow ? AppSpacing.md : AppSpacing.xl,
              MediaQuery.paddingOf(context).top + 64,
              AppSpacing.lg,
              isNarrow ? AppSpacing.lg : 96,
            ),
            child: Row(
              crossAxisAlignment:
                  isNarrow ? CrossAxisAlignment.center : CrossAxisAlignment.end,
              children: [
                SkeletonBox(width: avatarSize, height: avatarSize, circle: true),
                SizedBox(width: isNarrow ? AppSpacing.md : AppSpacing.xl),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SkeletonLine(
                        style: texts.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                        widthFactor: isNarrow ? 0.24 : 0.12,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      SkeletonLine(
                        style: texts.displaySmall?.copyWith(
                          fontSize: nameSize,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -2,
                        ),
                        widthFactor: isNarrow ? 0.72 : 0.5,
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      SkeletonLine(
                        style: texts.bodyMedium,
                        widthFactor: isNarrow ? 0.56 : 0.3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Зеркало `_ActionsRow`.
class SkeletonProfileActions extends StatelessWidget {
  const SkeletonProfileActions({super.key, required this.isOwnProfile});

  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    // У чужого профиля вместо кнопок — только отступ.
    if (!isOwnProfile) return const SizedBox(height: AppSpacing.md);

    return const Skeleton(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Row(
          children: [
            SkeletonSlot(
              reserve: IconButton(
                onPressed: null,
                icon: Icon(Icons.settings_outlined),
              ),
              child: SkeletonIcon(),
            ),
            SizedBox(width: AppSpacing.sm),
            SkeletonSlot(
              reserve: IconButton(
                onPressed: null,
                icon: Icon(Icons.more_horiz_rounded),
              ),
              child: SkeletonIcon(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Зеркало `_TrackRow` из профиля.
class SkeletonProfileTrackRow extends StatelessWidget {
  const SkeletonProfileTrackRow({super.key, this.index = 0});

  final int index;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Center(
              child: SkeletonLine(
                style: texts.bodySmall,
                width: _labelWidth(context, '00', texts.bodySmall),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SkeletonBox(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonLine(
                  style: texts.titleSmall,
                  widthFactor: _titleFactor(index),
                ),
                // Между названием и исполнителем у настоящей строки
                // промежутка нет.
                SkeletonLine(
                  style: texts.bodySmall,
                  widthFactor: _subtitleFactor(index),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Зеркало `_TrackSection`: заголовок раздела и строки под ним.
class SkeletonProfileTrackSection extends StatelessWidget {
  const SkeletonProfileTrackSection({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Skeleton(
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonLine(style: texts.titleLarge, widthFactor: 0.46),
                  const SizedBox(height: 2),
                  SkeletonLine(style: texts.bodySmall, widthFactor: 0.3),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < itemCount; i++)
              SkeletonProfileTrackRow(index: i),
          ],
        ),
      ),
    );
  }
}
