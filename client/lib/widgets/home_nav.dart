import 'package:flutter/material.dart';

import '../theme.dart';
import '../utils/local_store.dart';

class HomeDestination {
  const HomeDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<HomeDestination> kHomeDestinations = [
  HomeDestination(
    icon: Icons.radio_outlined,
    selectedIcon: Icons.radio_rounded,
    label: 'Сейчас',
  ),
  HomeDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Музыка',
  ),
  HomeDestination(
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    label: 'Друзья',
  ),
];

class HomeBottomNav extends StatelessWidget {
  const HomeBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.unreadFriendRequests = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int unreadFriendRequests;

  @override
  Widget build(BuildContext context) {
    const destinations = kHomeDestinations;

    return NavigationBar(
      selectedIndex: currentIndex.clamp(0, destinations.length - 1),
      onDestinationSelected: onSelected,
      destinations: [
        for (var i = 0; i < destinations.length; i++)
          NavigationDestination(
            icon: _maybeBadge(context, Icon(destinations[i].icon), i),
            selectedIcon: _maybeBadge(context, Icon(destinations[i].selectedIcon), i),
            label: destinations[i].label,
            tooltip: destinations[i].label,
          ),
      ],
    );
  }

  /// Счётчик непрочитанных на вкладке «Друзья».
  ///
  /// Badge — штатный виджет Material 3. Раньше значок собирался вручную из
  /// Stack + Positioned + Container с жёстко заданным Colors.yellow[700]:
  /// он не менялся вместе с темой, съезжал при другом размере шрифта и не
  /// озвучивался программами чтения с экрана.
  Widget _maybeBadge(BuildContext context, Widget icon, int index) {
    if (index != 2 || unreadFriendRequests <= 0) return icon;
    return Badge.count(
      count: unreadFriendRequests,
      backgroundColor: context.colors.error,
      textColor: context.colors.onError,
      child: icon,
    );
  }
}

/// Боковая навигация (широкая раскладка).
///
/// Заменяет рукописную панель на ~90 строк с самодельным индикатором на
/// AnimatedPositioned. У штатного NavigationRail индикатор, состояния
/// наведения, доступность и поддержка темы уже есть; расхождение размеров
/// пунктов и индикатора, которое приходилось согласовывать вручную через
/// константы _itemHeight/_itemPadding, исчезает как класс задач./// Боковая панель широкой раскладки.
///
/// Раньше она раскрывалась по наведению мыши и схлопывалась обратно. Это
/// казалось экономным, но на деле мешало: подписи появлялись и исчезали, а
/// на панель приходилось «наводиться», чтобы понять, где находишься.
///
/// Теперь панель открыта всегда, а ширину можно потянуть за правый край —
/// как в Spotify. Значение сохраняется, поэтому подстраивать его каждый
/// запуск не нужно.
class HomeNavigationRail extends StatefulWidget {
  const HomeNavigationRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    this.unreadFriendRequests = 0,
    this.onCreateSession,
    this.onFindFriends,
    this.onOpenLiked,
    this.onOpenHistory,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int unreadFriendRequests;

  final VoidCallback? onCreateSession;
  final VoidCallback? onFindFriends;
  final VoidCallback? onOpenLiked;
  final VoidCallback? onOpenHistory;

  @override
  State<HomeNavigationRail> createState() => _HomeNavigationRailState();
}

class _HomeNavigationRailState extends State<HomeNavigationRail> {
  static const double _minWidth = 200;
  static const double _maxWidth = 340;
  static const double _defaultWidth = 240;

  late double _width;

  bool _hoveringHandle = false;

  @override
  void initState() {
    super.initState();
    _width = LocalStore.readDouble(StoreKeys.railWidth, defaultValue: _defaultWidth)
        .clamp(_minWidth, _maxWidth);
  }

  void _onDrag(DragUpdateDetails details) {
    setState(() {
      _width = (_width + details.delta.dx).clamp(_minWidth, _maxWidth);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    LocalStore.saveDouble(StoreKeys.railWidth, _width);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const destinations = kHomeDestinations;

    return Row(
      children: [
        Container(
          width: _width,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: AppRadius.large,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _RailHeader(),
              const SizedBox(height: AppSpacing.sm),

              for (var i = 0; i < destinations.length; i++)
                _RailItem(
                  destination: destinations[i],
                  selected: widget.currentIndex == i,
                  badgeCount: i == 2 ? widget.unreadFriendRequests : 0,
                  onTap: () => widget.onSelected(i),
                ),

              const _RailDivider(),

              const _RailSectionTitle('Быстро'),
              if (widget.onCreateSession != null)
                _RailAction(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Новая сессия',
                  onTap: widget.onCreateSession!,
                ),
              if (widget.onFindFriends != null)
                _RailAction(
                  icon: Icons.person_search_outlined,
                  label: 'Найти друзей',
                  onTap: widget.onFindFriends!,
                ),

              const _RailDivider(),

              const _RailSectionTitle('Библиотека'),
              if (widget.onOpenLiked != null)
                _RailAction(
                  icon: Icons.favorite_border_rounded,
                  label: 'Любимые треки',
                  onTap: widget.onOpenLiked!,
                ),
              if (widget.onOpenHistory != null)
                _RailAction(
                  icon: Icons.history_rounded,
                  label: 'История',
                  onTap: widget.onOpenHistory!,
                ),

              const Spacer(),
            ],
          ),
        ),

        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => setState(() => _hoveringHandle = true),
          onExit: (_) => setState(() => _hoveringHandle = false),
          child: GestureDetector(
            onHorizontalDragUpdate: _onDrag,
            onHorizontalDragEnd: _onDragEnd,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: AppSpacing.sm,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _hoveringHandle ? 1 : 0,
                  duration: AppMotion.short,
                  child: Container(
                    width: 4,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.onSurfaceVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Пункт навигации в панели.
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final HomeDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: selected ? colors.primary.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: AppRadius.medium,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 4,
            ),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.titleSmall?.copyWith(
                      color: selected ? colors.onSurface : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.error,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: texts.labelSmall?.copyWith(
                        color: colors.onError,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Второстепенное действие в панели — тоньше и бледнее пунктов навигации.
class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.medium,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.onSurfaceVariant),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailSectionTitle extends StatelessWidget {
  const _RailSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: context.texts.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Divider(height: 1, color: context.colors.outlineVariant),
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Logo(colors: colors),
          const SizedBox(width: AppSpacing.sm + 4),
          Text(
            'SyncM',
            style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.small,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.graphic_eq_rounded, color: colors.onPrimaryContainer, size: 22),
    );
  }
}