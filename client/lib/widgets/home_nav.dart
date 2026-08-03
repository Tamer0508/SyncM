import 'package:flutter/material.dart';

import '../theme.dart';

class HomeDestination {
  const HomeDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.desktopOnly = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool desktopOnly;
}

const List<HomeDestination> kHomeDestinations = [
  HomeDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Главная',
  ),
  HomeDestination(
    icon: Icons.people_outline_rounded,
    selectedIcon: Icons.people_rounded,
    label: 'Друзья',
  ),
  HomeDestination(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Профиль',
  ),
  HomeDestination(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: 'Настройки',
    desktopOnly: true,
  ),
];

List<HomeDestination> homeDestinationsFor({required bool isDesktop}) =>
    isDesktop ? kHomeDestinations : kHomeDestinations.where((d) => !d.desktopOnly).toList();

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
    final destinations = homeDestinationsFor(isDesktop: false);

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

  Widget _maybeBadge(BuildContext context, Widget icon, int index) {
    if (index != 1 || unreadFriendRequests <= 0) return icon;
    return Badge.count(
      count: unreadFriendRequests,
      backgroundColor: context.colors.error,
      textColor: context.colors.onError,
      child: icon,
    );
  }
}

class HomeNavigationRail extends StatefulWidget {
  const HomeNavigationRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
    required this.onToggleTheme,
    required this.isDark,
    this.unreadFriendRequests = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onToggleTheme;
  final bool isDark;
  final int unreadFriendRequests;

  @override
  State<HomeNavigationRail> createState() => _HomeNavigationRailState();
}

class _HomeNavigationRailState extends State<HomeNavigationRail> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final destinations = homeDestinationsFor(isDesktop: true);

    return MouseRegion(
      onEnter: (_) => setState(() => _expanded = true),
      onExit: (_) => setState(() => _expanded = false),
      child: AnimatedContainer(
        duration: AppMotion.medium,
        curve: AppMotion.emphasized,
        width: _expanded ? 220 : 88,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          border: Border(right: BorderSide(color: colors.outlineVariant)),
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
            child: IntrinsicHeight(
              child: NavigationRail(
                extended: _expanded,
                backgroundColor: Colors.transparent,
                selectedIndex: widget.currentIndex.clamp(0, destinations.length - 1),
                onDestinationSelected: widget.onSelected,
                labelType: _expanded ? null : NavigationRailLabelType.none,
                leading: _RailHeader(expanded: _expanded),
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: IconButton(
                        onPressed: widget.onToggleTheme,
                        tooltip: widget.isDark ? 'Светлая тема' : 'Тёмная тема',
                        icon: AnimatedSwitcher(
                          duration: AppMotion.short,
                          transitionBuilder: (child, animation) => RotationTransition(
                            turns: Tween<double>(begin: 0.6, end: 1).animate(animation),
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                          child: Icon(
                            widget.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                            key: ValueKey(widget.isDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                destinations: [
                  for (var i = 0; i < destinations.length; i++)
                    NavigationRailDestination(
                      icon: _maybeBadge(context, Icon(destinations[i].icon), i),
                      selectedIcon: _maybeBadge(context, Icon(destinations[i].selectedIcon), i),
                      label: Text(destinations[i].label),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _maybeBadge(BuildContext context, Widget icon, int index) {
    if (index != 1 || widget.unreadFriendRequests <= 0) return icon;
    return Badge.count(
      count: widget.unreadFriendRequests,
      backgroundColor: context.colors.error,
      textColor: context.colors.onError,
      child: icon,
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: AnimatedSwitcher(
        duration: AppMotion.short,
        child: expanded
            ? Row(
                key: const ValueKey('wide'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Logo(colors: colors),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Text(
                    'SyncM',
                    style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              )
            : _Logo(key: const ValueKey('narrow'), colors: colors),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({super.key, required this.colors});

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