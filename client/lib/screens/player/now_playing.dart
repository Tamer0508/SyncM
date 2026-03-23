import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  double _position = 0.2; // fraction
  

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
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            // Artwork
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              height: MediaQuery.of(context).size.width - 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.artworkUrl != null && widget.artworkUrl!.isNotEmpty
                  ? CachedNetworkImage(imageUrl: widget.artworkUrl!, fit: BoxFit.cover, placeholder: (_, __) => Container(color: Colors.grey[800]), errorWidget: (_, __, ___) => Container(color: Colors.grey[800], child: const Icon(Icons.music_note, size: 96, color: Colors.white60)))
                  : Container(color: Colors.grey[800], child: const Icon(Icons.music_note, size: 96, color: Colors.white60)),
              ),
            ),
            const SizedBox(height: 18),
            // Title / Artist
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title ?? 'Unknown Title', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    widget.artist ?? 'Unknown Artist',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodyMedium?.color == null ? null : theme.textTheme.bodyMedium!.color!.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  Slider(value: _position, onChanged: (v) => setState(() => _position = v)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [Text('0:42', style: TextStyle(color: Colors.white54)), Text('-1:13', style: TextStyle(color: Colors.white54))],
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Controls
            Consumer<PlaybackProvider>(builder: (ctx, pb, _) {
              final playing = pb.isPlaying;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(onPressed: () {}, icon: const Icon(Icons.shuffle, color: Colors.white70)),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.skip_previous, color: Colors.white70, size: 36)),
                    GestureDetector(
                      onTap: () => pb.togglePlay(),
                      child: Container(
                        decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(8),
                        child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 36),
                      ),
                    ),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.skip_next, color: Colors.white70, size: 36)),
                    IconButton(onPressed: () {}, icon: const Icon(Icons.repeat, color: Colors.white70)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
