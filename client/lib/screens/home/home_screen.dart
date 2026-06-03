import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';
import 'package:syncm/screens/playlist/playlist_tracks_screen.dart';
import 'package:syncm/screens/settings/settings_screen.dart';
import 'package:syncm/services/socket_service.dart';
import '../../widgets/playlist_card.dart';
import '../../widgets/scrollable_playlist_row.dart';
import '../../widgets/interactive_card.dart';
import '../../widgets/mini_player.dart';
import '../../providers/session_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playback_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/friends_provider.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';
import '../../utils/notifications.dart';

class _RailIconWidget extends StatefulWidget {
  final IconData icon;
  final bool selected;
  const _RailIconWidget({Key? key, required this.icon, required this.selected}) : super(key: key);
  @override
  State<_RailIconWidget> createState() => _RailIconWidgetState();
}

class _RailIconWidgetState extends State<_RailIconWidget> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final bgColor = widget.selected ? primary : (_hover ? primary.withOpacity(0.12) : Colors.transparent);
    final iconColor = widget.selected ? Colors.white : theme.iconTheme.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: widget.selected
              ? [BoxShadow(color: primary.withOpacity(0.16), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Icon(widget.icon, color: iconColor, size: 22),
      ),
    );
  }
}

class _GlowBackground extends StatefulWidget {
  final Color dominantColor;
  final Color vibrantColor;
  const _GlowBackground({Key? key, required this.dominantColor, required this.vibrantColor}) : super(key: key);
  @override
  State<_GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<_GlowBackground> with TickerProviderStateMixin {
  late AnimationController _colorController;
  late Animation<Color?> _dominantAnim;
  late Animation<Color?> _vibrantAnim;
  Color _currentDominant = Colors.blueGrey.shade800;
  Color _currentVibrant = Colors.blueGrey.shade600;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _dominantAnim = ColorTween(begin: _currentDominant, end: widget.dominantColor).animate(_colorController);
    _vibrantAnim = ColorTween(begin: _currentVibrant, end: widget.vibrantColor).animate(_colorController);
    _colorController.addListener(() {
      setState(() {
        _currentDominant = _dominantAnim.value!;
        _currentVibrant = _vibrantAnim.value!;
      });
    });
    _colorController.forward();
  }

  @override
  void didUpdateWidget(covariant _GlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dominantColor != widget.dominantColor || oldWidget.vibrantColor != widget.vibrantColor) {
      _dominantAnim = ColorTween(begin: _currentDominant, end: widget.dominantColor).animate(_colorController);
      _vibrantAnim = ColorTween(begin: _currentVibrant, end: widget.vibrantColor).animate(_colorController);
      _colorController
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.2,
          colors: [
            _currentVibrant.withOpacity(0.3),
            _currentDominant.withOpacity(0.2),
          ],
        ),
      ),
    );
  }
}

class _NowPlayingPanelCompact extends StatefulWidget {
  const _NowPlayingPanelCompact({Key? key}) : super(key: key);
  @override
  State<_NowPlayingPanelCompact> createState() => _NowPlayingPanelCompactState();
}

class _NowPlayingPanelCompactState extends State<_NowPlayingPanelCompact> {
  
  double _dragValue = 0.0;
  bool _dragging = false;
  String? _lastTrackUri;
  Color _dominantColor = Colors.blueGrey.shade800;
  Color _vibrantColor = Colors.blueGrey.shade600;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshPaletteIfNeeded();
  }

  void _refreshPaletteIfNeeded() {
    final pb = Provider.of<PlaybackProvider>(context, listen: false);
    final track = pb.currentTrack;
    if (track == null) return;
    final uri = track['uri'] as String?;
    if (uri == _lastTrackUri) return;
    _lastTrackUri = uri;
    final imageUrl = track['imageUrl'] as String?;
    if (imageUrl != null && pb.paletteCache.containsKey(imageUrl)) {
      final p = pb.paletteCache[imageUrl]!;
      _applyPalette(
        p.dominantColor?.color ?? Colors.blueGrey.shade800,
        p.vibrantColor?.color ?? (p.lightVibrantColor?.color ?? Colors.blueGrey.shade600),
      );
    } else {
      _extractPalette(pb);
    }
  }

  Future<void> _extractPalette(PlaybackProvider pb) async {
    final imageBytes = pb.currentImageBytes;
    final imageUrl = pb.currentTrack?['imageUrl'] as String?;
    try {
      late ImageProvider provider;
      if (imageBytes != null) {
        provider = MemoryImage(imageBytes);
      } else if (imageUrl != null && imageUrl.isNotEmpty) {
        provider = NetworkImage(imageUrl);
      } else {
        return;
      }
      final palette = await PaletteGenerator.fromImageProvider(provider, size: const Size(200, 200), maximumColorCount: 16);
      if (!mounted) return;
      if (imageUrl != null) pb.paletteCache[imageUrl] = palette;
      _applyPalette(
        palette.dominantColor?.color ?? Colors.blueGrey.shade800,
        palette.vibrantColor?.color ?? (palette.lightVibrantColor?.color ?? Colors.blueGrey.shade600),
      );
    } catch (_) {}
  }

  void _applyPalette(Color dominant, Color vibrant) {
    if (!mounted) return;
    setState(() {
      _dominantColor = dominant;
      _vibrantColor = vibrant;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<PlaybackProvider>(
      builder: (_, pb, __) {
        final track = pb.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final currentUri = track['uri'] as String?;
        if (currentUri != _lastTrackUri) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshPaletteIfNeeded();
          });
        }
        final title = track['title'] ?? '';
        final artist = track['artist'] ?? '';
        final imageBytes = pb.currentImageBytes;
        final imageUrl = track['imageUrl'] as String?;
        final durationMs = pb.durationMs;
        final positionMs = pb.positionMs;
        final fraction = durationMs > 0
            ? (_dragging ? _dragValue : (positionMs / durationMs).clamp(0.0, 1.0))
            : 0.0;

        final textColor = theme.colorScheme.onSurface;
        final subtitleColor = theme.colorScheme.onSurface.withOpacity(0.7);
        final timeColor = theme.colorScheme.onSurface.withOpacity(0.6);
        final iconColor = theme.iconTheme.color ?? theme.colorScheme.onSurface;
        final inactiveTrackColor = theme.colorScheme.onSurface.withOpacity(0.24);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: theme.shadowColor.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _GlowBackground(dominantColor: _dominantColor, vibrantColor: _vibrantColor),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageBytes != null
                            ? Image.memory(imageBytes, width: 120, height: 120, fit: BoxFit.cover)
                            : imageUrl != null && imageUrl.isNotEmpty
                                ? Image.network(imageUrl, width: 120, height: 120, fit: BoxFit.cover)
                                : Container(
                                    width: 120,
                                    height: 120,
                                    color: theme.colorScheme.primary.withOpacity(0.2),
                                    child: Icon(Icons.music_note, size: 48, color: theme.colorScheme.primary),
                                  ),
                      ),
                      const SizedBox(height: 12),
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: textColor),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(artist,
                          style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      _CompactProgressBar(
                        fraction: fraction,
                        onSeek: (val) {
                          setState(() { _dragValue = val; _dragging = true; });
                        },
                        onSeekEnd: (val) {
                          setState(() => _dragging = false);
                          pb.seekTo((val * durationMs).toInt());
                        },
                        activeColor: _vibrantColor,
                        inactiveColor: inactiveTrackColor,
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatMs(positionMs), style: TextStyle(color: timeColor, fontSize: 12)),
                            Text(_formatMs(durationMs), style: TextStyle(color: timeColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(Icons.shuffle,
                                color: pb.shuffleActive
                                    ? _vibrantColor
                                    : iconColor.withOpacity(0.7),
                                size: 22),
                            onPressed: () => pb.setShuffle(!pb.shuffleActive),
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_previous, size: 28, color: iconColor),
                            onPressed: () { pb.skipPrevious(); setState(() => _dragValue = 0); },
                          ),
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: _vibrantColor),
                            child: IconButton(
                              icon: Icon(pb.isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: theme.colorScheme.onPrimary, size: 28),
                              onPressed: () => pb.togglePlay(),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next, size: 28, color: iconColor),
                            onPressed: () { pb.skipNext(); setState(() => _dragValue = 0); },
                          ),
                          IconButton(
                            icon: Icon(
                              pb.repeatMode == 'track' ? Icons.repeat_one : Icons.repeat,
                              color: pb.repeatActive ? _vibrantColor : iconColor.withOpacity(0.7),
                              size: 22,
                            ),
                            onPressed: () => pb.cycleRepeatMode(),
                          ),
                        ],
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

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _CompactProgressBar extends StatelessWidget {
  final double fraction;
  final Function(double) onSeek;
  final Function(double) onSeekEnd;
  final Color activeColor;
  final Color inactiveColor;
  const _CompactProgressBar({
    Key? key,
    required this.fraction,
    required this.onSeek,
    required this.onSeekEnd,
    required this.activeColor,
    required this.inactiveColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          final box = context.findRenderObject() as RenderBox;
          final localX = details.localPosition.dx.clamp(0.0, box.size.width);
          onSeek(localX / box.size.width);
        },
        onHorizontalDragUpdate: (details) {
          final box = context.findRenderObject() as RenderBox;
          final localX = details.localPosition.dx.clamp(0.0, box.size.width);
          onSeek(localX / box.size.width);
        },
        onHorizontalDragEnd: (details) {
          final box = context.findRenderObject() as RenderBox;
          final localX = details.localPosition.dx.clamp(0.0, box.size.width);
          onSeekEnd(localX / box.size.width);
        },
        child: Container(
          height: 20,
          alignment: Alignment.centerLeft,
          child: Stack(
            children: [
              Container(height: 4, decoration: BoxDecoration(color: inactiveColor, borderRadius: BorderRadius.circular(2))),
              FractionallySizedBox(
                widthFactor: fraction,
                child: Container(height: 4, decoration: BoxDecoration(color: activeColor, borderRadius: BorderRadius.circular(2))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _railExpanded = false;
  List<dynamic> _customPlaylists = [];
  List<dynamic> _spotifyPlaylists = [];
  bool _loadingCustom = false;
  bool _loadingSpotify = false;
  Map<String, dynamic>? _selectedPlaylist;

  @override
  void initState() {
    super.initState();
    _loadAllPlaylists();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.user?.id;
    if (userId != null) {
      final socket = SocketService();
      socket.init(auth.api.baseUrl, userId);
      Provider.of<FriendsProvider>(context, listen: false).init(socket);
      final sessionProv = Provider.of<SessionProvider>(context, listen: false);
      sessionProv.init(socket);
      sessionProv.fetchMySessions();
      sessionProv.fetchInvites();
    }
  }

  Future<void> _loadAllPlaylists() async {
    if (mounted) setState(() { _loadingCustom = true; _loadingSpotify = true; });
    final api = Provider.of<AuthProvider>(context, listen: false).api;
    try {
      final custom = await api.getMyPlaylists();
      if (mounted) setState(() => _customPlaylists = custom);
    } catch (e) {
      if (mounted) showAppNotification(context, message: 'Ошибка загрузки своих плейлистов: $e', type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _loadingCustom = false);
    }
    try {
      final spotify = await api.getPlaylists();
      if (mounted) setState(() => _spotifyPlaylists = spotify);
    } catch (e) {
      if (mounted && e.toString().contains('Spotify не подключен') == false)
        showAppNotification(context, message: 'Ошибка загрузки Spotify плейлистов: $e', type: NotificationType.error);
    } finally {
      if (mounted) setState(() => _loadingSpotify = false);
    }
  }

  Widget _buildHomeTab() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InteractiveCard(
          margin: EdgeInsets.zero,
          borderRadius: 26,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Добро пожаловать в SyncM', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                'Обновлённый интерфейс для музыки и общения. Найдите друзей, создайте сессии и синхронизируйте любимый звук.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78), height: 1.5),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12, runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add), label: const Text('Новая сессия'),
                    onPressed: () => Navigator.of(context).pushNamed('/session/create'),
                    style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.person_search), label: const Text('Поиск друзей'),
                    onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Плейлисты', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            IconButton(icon: const Icon(Icons.add_box_outlined), onPressed: _createCustomPlaylist, tooltip: 'Создать плейлист'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [Tab(text: 'Мои'), Tab(text: 'Spotify')]),
                Expanded(
                  child: TabBarView(children: [_buildPlaylistsTab(true), _buildPlaylistsTab(false)]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Приглашения в сессии', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Consumer<SessionProvider>(
              builder: (_, prov, __) {
                if (prov.invites.isEmpty) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () {
                    prov.markInvitesAsRead();
                    Navigator.of(context).pushNamed('/session/invites');
                  },
                  child: Text('Все (${prov.invites.length})'),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Consumer<SessionProvider>(
          builder: (_, prov, __) {
            if (prov.invitesLoading && prov.invites.isEmpty) {
              return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
            }
            if (prov.invites.isEmpty) {
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  child: Text(
                    'Нет входящих приглашений. Когда друг создаст сессию с вами, уведомление появится здесь.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.78),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return Column(
              children: prov.invites.take(3).map((invite) {
                final name = invite['name'] as String? ?? 'Сессия';
                final hostName = prov.hostNameForInvite(invite) ?? 'Друг';
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    tileColor: theme.colorScheme.primaryContainer.withOpacity(0.35),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                      child: Icon(Icons.music_note, color: theme.colorScheme.primary),
                    ),
                    title: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text('Приглашение от $hostName'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      prov.markInvitesAsRead();
                      Navigator.of(context).pushNamed('/session/invites');
                    },
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Активные сессии', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            TextButton(
              onPressed: () async => await Provider.of<SessionProvider>(context, listen: false).fetchMySessions(),
              child: const Text('Обновить'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Consumer<SessionProvider>(builder: (_, prov, __) {
          if (prov.loading) return Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
          if (prov.sessions.isEmpty)
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                child: Column(
                  children: [
                    Text('Нет активных сессий', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Создайте сессию и пригласите друзей, чтобы начать совместное прослушивание.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78)),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          return Column(
            children: prov.sessions
                .map((s) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        tileColor: theme.cardColor,
                        title: Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text('Host: ${s.id.substring(0, 6)}', style: theme.textTheme.bodySmall),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pushNamed('/session'),
                      ),
                    ))
                .toList(),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPlaylistsTab(bool isCustom) {
    final playlists = isCustom ? _customPlaylists : _spotifyPlaylists;
    final loading = isCustom ? _loadingCustom : _loadingSpotify;
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (playlists.isEmpty)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isCustom ? 'Нет своих плейлистов' : 'Нет Spotify плейлистов', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: Icon(isCustom ? Icons.add : Icons.link),
              label: Text(isCustom ? 'Создать плейлист' : 'Подключить Spotify'),
              onPressed: () => isCustom ? _createCustomPlaylist() : Navigator.of(context).pushNamed('/profile'),
            ),
          ],
        ),
      );
    return ScrollablePlaylistRow(
      itemCount: playlists.length,
      itemBuilder: (_, i) {
        final p = playlists[i];
        return PlaylistCard(
          name: p['name'] ?? '', description: p['description'] ?? '', imageUrl: p['imageUrl'],
          onTap: () {
            if (isDesktop) {
              setState(() { _selectedPlaylist = {'id': p['id'], 'name': p['name'], 'imageUrl': p['imageUrl'], 'isCustom': isCustom}; });
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaylistTracksScreen(playlistId: p['id'] ?? '', playlistName: p['name'] ?? '', imageUrl: p['imageUrl'], isCustom: isCustom),
              ));
            }
          },
        );
      },
    );
  }

  Future<void> _createCustomPlaylist() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()), child: const Text('Создать')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      try {
        final api = Provider.of<AuthProvider>(context, listen: false).api;
        await api.createCustomPlaylist(name);
        await _loadAllPlaylists();
      } catch (e) {
        if (mounted) showAppNotification(context, message: 'Ошибка создания плейлиста: $e', type: NotificationType.error);
      }
    }
  }

  Widget _buildRightPanel() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Панель', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          InteractiveCard(
            borderRadius: 16, padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Быстрые действия', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add), label: const Text('Новая сессия'),
                  onPressed: () => Navigator.of(context).pushNamed('/session/create'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_search), label: const Text('Найти друзей'),
                  onPressed: () => Navigator.of(context).pushNamed('/friends/search'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Consumer<PlaybackProvider>(
              builder: (_, pb, __) {
                if (pb.currentTrack == null)
                  return InteractiveCard(
                    borderRadius: 16, padding: const EdgeInsets.all(16),
                    child: Center(child: Text('Трек не выбран', style: theme.textTheme.bodyMedium)),
                  );
                return const _NowPlayingPanelCompact();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader() {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          if (_selectedPlaylist != null)
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _selectedPlaylist = null)),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                _selectedPlaylist != null ? _selectedPlaylist!['name'] ?? 'Плейлист' : ['Главная', 'Друзья', 'Профиль', 'Настройки'][_currentIndex],
                key: ValueKey(_selectedPlaylist?['id'] ?? _currentIndex),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Row(
            children: [
              if (_currentIndex == 1) ...[
                IconButton(icon: const Icon(Icons.person_add_alt_1), onPressed: () => Navigator.of(context).pushNamed('/friends/search')),
                IconButton(icon: const Icon(Icons.notifications_none), onPressed: () => Navigator.of(context).pushNamed('/friends/requests')),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () async => await Provider.of<FriendsProvider>(context, listen: false).fetchFriends()),
              ] else if (_currentIndex == 0) ...[
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.mail_outline),
                      if (Provider.of<SessionProvider>(context).unreadInvitesCount > 0)
                        Positioned(
                          top: -5,
                          right: -10,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              '${Provider.of<SessionProvider>(context).unreadInvitesCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => Navigator.of(context).pushNamed('/session/invites'),
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: () => Navigator.of(context).pushNamed('/session/create')),
              ],
              if (_currentIndex == 2) ...[
                IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.of(context).pushNamed('/settings')),
              ],
              IconButton(icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode), onPressed: () => themeProvider.toggleTheme()),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        if (!isDesktop && _currentIndex > 2) _currentIndex = 0;
        final unreadCount = Provider.of<FriendsProvider>(context).unreadCount;
        final tabsMobile = [_buildHomeTab(), FriendsScreen(embedded: true), ProfileScreen(embedded: true)];
        final tabsDesktop = [_buildHomeTab(), FriendsScreen(embedded: true), ProfileScreen(embedded: true), const SettingsScreen()];
        final miniPlayerWidget = const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: MiniPlayer());
        final navItems = [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Главная'),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.people),
                if (unreadCount > 0)
                  Positioned(
                    top: -5,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.yellow[700],
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Друзья',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Профиль'),
        ];
        final mobileBottomNav = !isDesktop
            ? SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    miniPlayerWidget,
                    Theme.of(context).platform == TargetPlatform.iOS
                        ? CupertinoTabBar(
                            currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
                            activeColor: Theme.of(context).colorScheme.primary,
                            items: navItems,
                          )
                        : BottomNavigationBar(
                            currentIndex: _currentIndex, onTap: (i) => setState(() => _currentIndex = i),
                            items: navItems,
                          ),
                  ],
                ),
              )
            : null;

        return Scaffold(
          body: isDesktop
              ? Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _railExpanded ? 220 : 92,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _railExpanded = true),
                        onExit: (_) => setState(() => _railExpanded = false),
                        child: NavigationRail(
                          labelType: _railExpanded ? NavigationRailLabelType.all : NavigationRailLabelType.none,
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                                  child: Text('SyncM', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(icon: Icon(themeProvider.isDark ? Icons.dark_mode : Icons.light_mode), onPressed: () => themeProvider.toggleTheme()),
                              const SizedBox(height: 8),
                            ],
                          ),
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (i) => setState(() { _currentIndex = i; _selectedPlaylist = null; }),
                          destinations: [
                            NavigationRailDestination(icon: _RailIconWidget(icon: Icons.home, selected: _currentIndex == 0), selectedIcon: _RailIconWidget(icon: Icons.home, selected: _currentIndex == 0), label: const Text('Главная')),
                            NavigationRailDestination(icon: _RailIconWidget(icon: Icons.people, selected: _currentIndex == 1), selectedIcon: _RailIconWidget(icon: Icons.people, selected: _currentIndex == 1), label: const Text('Друзья')),
                            NavigationRailDestination(icon: _RailIconWidget(icon: Icons.person, selected: _currentIndex == 2), selectedIcon: _RailIconWidget(icon: Icons.person, selected: _currentIndex == 2), label: const Text('Профиль')),
                            NavigationRailDestination(icon: _RailIconWidget(icon: Icons.settings, selected: _currentIndex == 3), selectedIcon: _RailIconWidget(icon: Icons.settings, selected: _currentIndex == 3), label: const Text('Настройки')),
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildDesktopHeader(),
                                Expanded(
                                  child: _selectedPlaylist != null
                                      ? PlaylistTracksScreen(playlistId: _selectedPlaylist!['id'] ?? '', playlistName: _selectedPlaylist!['name'] ?? '', imageUrl: _selectedPlaylist!['imageUrl'], isCustom: _selectedPlaylist!['isCustom'] ?? false, embedded: true)
                                      : Center(
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 1100),
                                            child: AnimatedSwitcher(
                                              duration: const Duration(milliseconds: 280),
                                              child: KeyedSubtree(key: ValueKey('desktop_$_currentIndex'), child: tabsDesktop[_currentIndex]),
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 320, child: _buildRightPanel()),
                        ],
                      ),
                    ),
                  ],
                )
              : SafeArea(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: KeyedSubtree(key: ValueKey('mobile_$_currentIndex'), child: tabsMobile[_currentIndex]),
                  ),
                ),
          bottomNavigationBar: isDesktop ? null : mobileBottomNav,
        );
      },
    );
  }
}