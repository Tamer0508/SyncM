import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/playback_provider.dart';

class NowPlayingScreen extends StatefulWidget {
  final String? title;
  final String? artist;
  final String? artworkUrl;

  const NowPlayingScreen({Key? key, this.title, this.artist, this.artworkUrl}) : super(key: key);

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  double _position = 0.2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: theme.iconTheme,
        actions: [
          IconButton(onPressed: () {}, icon: Icon(Icons.more_vert, color: theme.iconTheme.color)),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: MediaQuery.of(context).size.width - 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 12))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.artworkUrl != null && widget.artworkUrl!.isNotEmpty
                    ? CachedNetworkImage(imageUrl: widget.artworkUrl!, fit: BoxFit.cover, placeholder: (_, __) => Container(color: theme.colorScheme.surfaceVariant), errorWidget: (_, __, ___) => Container(color: theme.colorScheme.surfaceVariant, child: const Icon(Icons.music_note, size: 96, color: Colors.white60)))
                    : Container(
                        color: theme.colorScheme.surfaceVariant,
                        child: Icon(Icons.music_note, size: 96, color: theme.colorScheme.primary),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title ?? 'Unknown Title', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    widget.artist ?? 'Unknown Artist',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.75)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Slider(
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.surfaceVariant,
                    value: _position,
                    onChanged: (v) => setState(() => _position = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0:42', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
                      Text('-1:13', style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withOpacity(0.7))),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            Consumer<PlaybackProvider>(builder: (ctx, pb, _) {
              final playing = pb.isPlaying;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () {}, icon: Icon(Icons.shuffle, color: theme.iconTheme.color)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.skip_previous, color: theme.iconTheme.color, size: 36)),
                    GestureDetector(
                      onTap: () => pb.togglePlay(),
                      child: Container(
                        decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(12),
                        child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                      ),
                    ),
                    IconButton(onPressed: () {}, icon: Icon(Icons.skip_next, color: theme.iconTheme.color, size: 36)),
                    IconButton(onPressed: () {}, icon: Icon(Icons.repeat, color: theme.iconTheme.color)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
