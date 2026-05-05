import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';

class PlaylistTracksScreen extends StatefulWidget {
  final String playlistId;
  final String playlistName;
  final String? imageUrl;

  const PlaylistTracksScreen({
    Key? key,
    required this.playlistId,
    required this.playlistName,
    this.imageUrl,
  }) : super(key: key);

  @override
  State<PlaylistTracksScreen> createState() => _PlaylistTracksScreenState();
}

class _PlaylistTracksScreenState extends State<PlaylistTracksScreen> {
  List<dynamic> _tracks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final api = Provider.of<AuthProvider>(context, listen: false).api;
      final tracks = await api.getPlaylistTracks(widget.playlistId);
      if (mounted) {
        setState(() {
          _tracks = tracks;
        });
      }
    } catch (e, stack) {
      print('Error loading tracks: $e');
      print(stack);
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.playlistName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              background: widget.imageUrl != null
                  ? Image.network(widget.imageUrl!, fit: BoxFit.cover)
                  : Container(color: theme.colorScheme.primary.withOpacity(0.3)),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text('Нет треков', style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.75))),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final t = _tracks[i];
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      margin: const EdgeInsets.only(bottom: 14),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        leading: t['imageUrl'] != null
                            ? Image.network(t['imageUrl'], width: 56, height: 56, fit: BoxFit.cover)
                            : Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceVariant,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(Icons.music_note, color: theme.colorScheme.primary),
                              ),
                        title: Text(t['name'] ?? '', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        subtitle: Text(t['artist'] ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.78))),
                      ),
                    );
                  },
                  childCount: _tracks.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
