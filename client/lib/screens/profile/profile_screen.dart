import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/spotify_link_service.dart';
import '../../theme.dart';
import '../../utils/artwork_color_store.dart';
import '../../utils/image_cache.dart';
import '../../utils/local_store.dart';
import '../../utils/error_utils.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/app_menu.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable_avatar.dart';
import '../settings/play_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.embedded = false,
    this.overrideArgs,
    this.onBack,
    this.onOpenSettings,
    this.onOpenHistory,
  });

  final bool embedded;

  final Map<String, dynamic>? overrideArgs;

  final VoidCallback? onBack;

  final VoidCallback? onOpenSettings;

  final VoidCallback? onOpenHistory;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profileData;
  String? _displayId;
  bool _loading = false;

  int _requestGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _determineTargetUser();
  }

  void _determineTargetUser() {
    final args = widget.overrideArgs ??
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final auth = Provider.of<AuthProvider>(context, listen: false);

    final targetId = (args != null && args['friendId'] != null)
        ? args['friendId'] as String
        : auth.user?.id;

    if (targetId != null && targetId != _displayId) {
      _displayId = targetId;
      _profileData = _cachedProfile(targetId);
      _loadProfile(targetId);
    }
  }

  static Map<String, dynamic>? _cachedProfile(String userId) {
    final all = LocalStore.readMap(StoreKeys.profiles);
    final saved = all?[userId];
    return saved is Map ? Map<String, dynamic>.from(saved) : null;
  }

  static void _saveProfile(String userId, Map<String, dynamic> data) {
    final all = LocalStore.readMap(StoreKeys.profiles) ?? <String, dynamic>{};
    all[userId] = data;

    if (all.length > 20) {
      final extra = all.keys.take(all.length - 20).toList();
      for (final key in extra) {
        all.remove(key);
      }
    }

    LocalStore.saveMap(StoreKeys.profiles, all).ignore();
  }

  Future<void> _loadProfile(String userId) async {
    final generation = ++_requestGeneration;

    if (_profileData == null) setState(() => _loading = true);

    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final data = await api.getUserProfile(userId);
      if (!mounted || generation != _requestGeneration) return;

      _saveProfile(userId, data);
      setState(() => _profileData = data);
    } catch (err) {
      if (!mounted || generation != _requestGeneration) return;
      if (_profileData == null) showError(context, err);
    } finally {
      if (mounted && generation == _requestGeneration && _loading) {
        setState(() => _loading = false);
      }
    }
  }

  bool get isOwnProfile {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return _displayId == auth.user?.id;
  }

  Future<void> _confirmBlock(BuildContext context, String name) async {
    final confirmed = await showConfirmDialog(
      context,
      icon: Icons.block_rounded,
      title: 'Заблокировать $name?',
      message: 'Он не найдёт вас в поиске, не сможет отправить заявку или '
          'позвать в сессию. Дружба будет удалена. Уведомления он не получит.',
      confirmLabel: 'Заблокировать',
    );

    if (!confirmed || !mounted) return;

    final targetId = _displayId;
    if (targetId == null) return;

    try {
      final ok = await context.read<AuthProvider>().api.blockUser(targetId);
      if (!mounted) return;

      if (ok) {
        context.read<FriendsProvider>().fetchFriends(refresh: true).ignore();
        showSuccess(context, '$name заблокирован');
        if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.of(context).pop();
        }
      } else {
        showError(context, 'Не удалось заблокировать', force: true);
      }
    } catch (err) {
      if (!mounted) return;
      showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final displayName = isOwnProfile
        ? (auth.user?.displayName ?? 'Профиль')
        : (_profileData?['displayName'] as String? ?? 'Друг');

    final avatarUrl = isOwnProfile
        ? auth.user?.effectiveAvatarUrl
        : _profileData?['avatarUrl'] as String?;

    final friendsCount = _profileData?['friendsCount'] as int? ?? 0;
    final mutualCount = _profileData?['mutualFriendsCount'] as int? ?? 0;

    final body = _loading && _profileData == null
        ? const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonProfileHeader(),
                // Ряд кнопок под шапкой — круглая шестерёнка и троеточие.
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      SkeletonBox(width: 44, height: 44, circle: true),
                      SizedBox(width: AppSpacing.md),
                      SkeletonBox(width: 28, height: 28, circle: true),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: SkeletonSectionHeader(titleWidth: 186),
                ),
                SizedBox(height: AppSpacing.sm),
                SkeletonProfileTrackList(itemCount: 3),
                SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: SkeletonSectionHeader(titleWidth: 148),
                ),
                SizedBox(height: AppSpacing.sm),
                SkeletonProfileTrackList(itemCount: 4),
              ],
            ),
          )
        : _ProfileContent(
            key: ValueKey(_displayId),
            isOwnProfile: isOwnProfile,
            displayName: displayName,
            avatarUrl: avatarUrl,
            friendsCount: friendsCount,
            mutualCount: mutualCount,
            profileData: _profileData,
            targetId: _displayId,
            onConnectSpotify: () => connectSpotify(context),
            onDisconnectSpotify: () => disconnectSpotify(context),
            onOpenSettings: widget.onOpenSettings ??
                () => Navigator.of(context).pushNamed('/settings'),
            onOpenHistory: widget.onOpenHistory ??
                () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const PlayHistoryScreen()),
                    ),
          );

    return Scaffold(
      backgroundColor: context.colors.surface,
      bottomNavigationBar: widget.embedded ? null : const MiniPlayerDock(),
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    if (widget.onBack != null || !widget.embedded)
                      _OverlayButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Назад',
                        onPressed: widget.onBack ??
                            () => Navigator.of(context).maybePop(),
                      ),
                    const Spacer(),
                    if (!isOwnProfile)
                      _OverlayButton(
                        icon: Icons.block_rounded,
                        tooltip: 'Заблокировать',
                        onPressed: () => _confirmBlock(context, displayName),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Содержимое профиля: шапка с градиентом и списки треков.
class _ProfileContent extends StatefulWidget {
  const _ProfileContent({
    super.key,
    required this.isOwnProfile,
    required this.displayName,
    required this.avatarUrl,
    required this.friendsCount,
    required this.mutualCount,
    required this.profileData,
    required this.targetId,
    required this.onConnectSpotify,
    required this.onDisconnectSpotify,
    required this.onOpenSettings,
    required this.onOpenHistory,
  });

  final bool isOwnProfile;
  final String displayName;
  final String? avatarUrl;
  final int friendsCount;
  final int mutualCount;
  final Map<String, dynamic>? profileData;
  final String? targetId;
  final VoidCallback onConnectSpotify;
  final VoidCallback onDisconnectSpotify;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;

  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent> {
  /// Цвет шапки, снятый с аватара.
  late final ValueNotifier<Color?> _heroColor =
      ValueNotifier<Color?>(ArtworkColorStore.cached(widget.avatarUrl));

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _liked = [];

  int _likedCount = 0;

  bool _loadingLists = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extractHeroColor();
      _loadLists();
    });
  }

  @override
  void didUpdateWidget(covariant _ProfileContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl) {
      _heroColor.value = ArtworkColorStore.cached(widget.avatarUrl);
      _extractHeroColor();
    }
  }

  @override
  void dispose() {
    _heroColor.dispose();
    super.dispose();
  }

  Future<void> _extractHeroColor() async {
    final url = widget.avatarUrl;
    if (url == null || url.isEmpty) return;
    if (_heroColor.value != null) return;

    final color = await ArtworkColorStore.resolve(url);
    if (!mounted || color == null) return;
    _heroColor.value = color;
  }

  Future<void> _loadLists() async {
    try {
      final api = context.read<AuthProvider>().api;

      if (widget.isOwnProfile) {
        final historyRequest = api.getPlayHistory(limit: 20);
        final likedRequest = api.getLikedTracks();

        final history = await historyRequest;
        final liked = await likedRequest;
        if (!mounted) return;

        setState(() {
          _history = history;
          _liked = liked
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .take(20)
              .toList();
        });
        return;
      }

      final id = widget.targetId;
      if (id == null) return;

      final data = await api.getUserActivity(id);
      if (!mounted) return;

      setState(() {
        _history = (data['history'] as List?)
                ?.whereType<Map>()
                .map(Map<String, dynamic>.from)
                .toList() ??
            [];
        _likedCount = data['likedCount'] as int? ?? 0;
      });
    } catch (err) {
      // Списки второстепенны: профиль полезен и без них.
      debugPrint('Не удалось загрузить списки профиля: $err');
    } finally {
      if (mounted) setState(() => _loadingLists = false);
    }
  }

  int get _likedTotal => widget.isOwnProfile ? _liked.length : _likedCount;

  String _buildSubtitle() {
    final sessions = widget.profileData?['sessionsCount'] as int? ?? 0;

    final parts = <String>[
      '${widget.friendsCount} ${_plural(widget.friendsCount, 'друг', 'друга', 'друзей')}',
      if (sessions > 0)
        '$sessions ${_plural(sessions, 'сессия', 'сессии', 'сессий')}',
      if (_likedTotal > 0) '$_likedTotal любимых',
      if (!widget.isOwnProfile && widget.mutualCount > 0)
        '${widget.mutualCount} общих',
    ];
    return parts.join(' • ');
  }

  String _plural(int n, String one, String few, String many) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return many;
    return switch (n % 10) {
      1 => one,
      2 || 3 || 4 => few,
      _ => many,
    };
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) => _Hero(
              colorSource: _heroColor,
              isNarrow: constraints.maxWidth < 700,
              displayName: widget.displayName,
              avatarUrl: widget.avatarUrl,
              subtitle: _buildSubtitle(),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: _ActionsRow(
            isOwnProfile: widget.isOwnProfile,
            onOpenSettings: widget.onOpenSettings,
            spotifyConnected:
                context.watch<AuthProvider>().user?.spotifyConnected == true,
            onConnect: widget.onConnectSpotify,
            onDisconnect: widget.onDisconnectSpotify,
          ),
        ),

        if (_loadingLists)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SkeletonProfileTrackList(itemCount: 3),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _TrackSection(
              title: 'Недавно слушали',
              hint: _history.isEmpty
                  ? (widget.isOwnProfile
                      ? 'Здесь появятся треки, которые вы включали'
                      : 'Ничего не показывается')
                  : (widget.isOwnProfile ? 'Видно только вам' : 'Последнее'),
              tracks: _history,
              onShowAll: (_history.isEmpty || !widget.isOwnProfile)
                  ? null
                  : widget.onOpenHistory,
            ),
          ),

          if (widget.isOwnProfile)
            SliverToBoxAdapter(
              child: _TrackSection(
                title: 'Любимые треки',
                hint: _liked.isEmpty
                    ? 'Отмечайте треки сердечком — они соберутся здесь'
                    : '${_liked.length} в подборке',
                tracks: _liked,
              ),
            ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
      ],
    );
  }
}

/// Шапка профиля с градиентом от цвета аватара.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.colorSource,
    required this.isNarrow,
    required this.displayName,
    required this.avatarUrl,
    required this.subtitle,
  });

  /// Цвет аватара: null, пока не посчитан.
  final ValueListenable<Color?> colorSource;
  final bool isNarrow;
  final String displayName;
  final String? avatarUrl;
  final String subtitle;

  Color _fallback(ColorScheme colors) {
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    return hasAvatar ? colors.surfaceContainerHighest : colors.primary;
  }

  static Color _shade(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.6))
        .withLightness(0.32)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final avatarSize = isNarrow ? 96.0 : 200.0;
    final nameSize = isNarrow ? 30.0 : 72.0;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Профиль',
          style: texts.labelLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: texts.displaySmall?.copyWith(
            fontSize: nameSize,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          subtitle,
          style: texts.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );

    final content = Padding(
      // Отступ сверху с запасом под системную строку и кнопку возврата,
      // которая лежит поверх градиента.
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
          _HeroAvatar(size: avatarSize, url: avatarUrl, name: displayName),
          SizedBox(width: isNarrow ? AppSpacing.md : AppSpacing.xl),
          Expanded(child: info),
        ],
      ),
    );

    return ValueListenableBuilder<Color?>(
      valueListenable: colorSource,
      child: content,
      builder: (context, value, child) {
        final hero = _shade(value ?? _fallback(colors));

        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: hero),
          duration: const Duration(milliseconds: 220),
          builder: (context, animated, child) => Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  animated ?? hero,
                  Color.lerp(animated ?? hero, colors.surface, 0.55)!,
                  colors.surface,
                ],
                stops:
                    isNarrow ? const [0.0, 0.65, 1.0] : const [0.0, 0.55, 1.0],
              ),
            ),
            child: child,
          ),
          child: child,
        );
      },
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({required this.size, required this.url, required this.name});

  final double size;
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          // Тень отделяет аватар от градиента: без неё он сливается с шапкой,
          // цвет которой снят с него же самого.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TappableAvatar(
        imageUrl: url,
        radius: size / 2,
        title: name,
        heroTag: 'profile-hero-$name',
      ),
    );
  }
}

/// Кнопки под шапкой.
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.isOwnProfile,
    required this.onOpenSettings,
    required this.spotifyConnected,
    required this.onConnect,
    required this.onDisconnect,
  });

  final bool isOwnProfile;
  final VoidCallback onOpenSettings;
  final bool spotifyConnected;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    if (!isOwnProfile) return const SizedBox(height: AppSpacing.md);

    final colors = context.colors;
    final texts = context.texts;
    final spotify = context.roles.spotify;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          IconButton.filledTonal(
            // Через обработчик, а не маршрутом: прямой pushNamed открывал
            // настройки во весь экран на широкой раскладке, закрывая боковую
            // панель — в отличие от всех остальных переходов.
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
          ),
          const SizedBox(width: AppSpacing.sm),
          AppMenuButton<String>(
            icon: Icons.more_horiz_rounded,
            tooltip: 'Ещё',
            onSelected: (value) {
              if (value == 'spotify') {
                spotifyConnected ? onDisconnect() : onConnect();
              }
            },
            entries: [
              AppMenuEntry(
                value: 'spotify',
                icon: spotifyConnected
                    ? Icons.link_off_rounded
                    : Icons.link_rounded,
                label: spotifyConnected
                    ? 'Отключить Spotify'
                    : 'Подключить Spotify',
                iconColor: spotify,
              ),
            ],
          ),
          const Spacer(),
          if (spotifyConnected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 16, color: spotify),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Spotify',
                  style: texts.labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: Colors.white,
        tooltip: tooltip,
      ),
    );
  }
}

/// Список треков с разворотом.
///
/// Горизонтальная лента здесь не подошла: у трека длинное название, в узкой
/// карточке оно обрезается, а прокрутка вбок внутри вертикального списка
/// конфликтует с основным жестом. Вертикальный список читается сразу, а
/// чтобы он не занимал пол-экрана, свёрнут до пяти строк.
class _TrackSection extends StatefulWidget {
  const _TrackSection({
    required this.title,
    required this.hint,
    required this.tracks,
    this.onShowAll,
  });

  final String title;
  final String hint;
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onShowAll;

  @override
  State<_TrackSection> createState() => _TrackSectionState();
}

class _TrackSectionState extends State<_TrackSection> {
  static const int _collapsedCount = 5;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final total = widget.tracks.length;
    final visible =
        _expanded ? total : (total < _collapsedCount ? total : _collapsedCount);
    final canExpand = total > _collapsedCount;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      // GestureDetector, а не InkWell.
      //
      // Нажатие в любом месте секции разворачивает и сворачивает её, но
      // заливка на всю площадь выглядела бы неуместно: подсветка размером
      // в пол-экрана читается как ошибка, а не как отклик. Отклик здесь даёт
      // само раскрытие списка.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: texts.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          widget.hint,
                          style: texts.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onShowAll != null)
                    TextButton(
                      onPressed: widget.onShowAll,
                      child: const Text('Все'),
                    ),
                  if (canExpand)
                    // Стрелка показывает, что секцию можно раскрыть, и
                    // поворачивается вместе с состоянием.
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: AppMotion.short,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            AnimatedSize(
              duration: AppMotion.medium,
              curve: AppMotion.emphasized,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (total == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: Text(
                        'Пока пусто',
                        style: texts.bodyMedium
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    )
                  else
                    for (var i = 0; i < visible; i++)
                      _TrackRow(
                        // Ключ по идентификатору трека: без него Flutter
                        // сопоставляет строки по позиции, и при раскрытии
                        // обложки на мгновение перескакивают между соседями.
                        key: ValueKey(widget.tracks[i]['spotifyUri'] ??
                            widget.tracks[i]['uri'] ??
                            'row-$i'),
                        track: widget.tracks[i],
                        index: i + 1,
                      ),
                ],
              ),
            ),

            if (canExpand)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  _expanded ? 'Свернуть' : 'Ещё ${total - visible}',
                  style:
                      texts.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Строка трека в списке профиля.
class _TrackRow extends StatelessWidget {
  const _TrackRow({super.key, required this.track, required this.index});

  final Map<String, dynamic> track;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    final name = track['trackName'] as String? ?? track['name'] as String? ?? '';
    final artist =
        track['artistName'] as String? ?? track['artist'] as String? ?? '';
    final image = track['imageUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index',
              textAlign: TextAlign.center,
              style: texts.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ClipRRect(
            // Квадрат со скруглением, а не круг: у трека есть обложка, и
            // круглая маска срезает её углы вместе с частью изображения.
            // Круглыми показывают исполнителей, а не песни.
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: SizedBox(
              width: 44,
              height: 44,
              child: image != null && image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: image,
                      cacheManager: AppImageCache.manager,
                      memCacheWidth: 132,
                      maxWidthDiskCache: 132,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          ColoredBox(color: colors.surfaceContainerHigh),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: colors.surfaceContainerHigh,
                        child: Icon(Icons.music_note_rounded,
                            size: 18, color: colors.onSurfaceVariant),
                      ),
                    )
                  : ColoredBox(
                      color: colors.surfaceContainerHigh,
                      child: Icon(Icons.music_note_rounded,
                          size: 18, color: colors.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: texts.titleSmall,
                ),
                if (artist.isNotEmpty)
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: texts.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}