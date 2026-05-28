import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
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
  Timer? _timer;
  int _positionMs = 0;
  bool _dragging = false;

  bool get _isWindows => defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _positionMs = Provider.of<PlaybackProvider>(context, listen: false).positionMs;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final pb = Provider.of<PlaybackProvider>(context, listen: false);
      if (pb.isPlaying && !_dragging) {
        if (_isWindows) {
          // На Windows берём позицию из провайдера (обновляется через polling)
          setState(() => _positionMs = pb.positionMs);
        } else {
          setState(() {
            _positionMs = (_positionMs + 1000).clamp(0, pb.durationMs);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<PlaybackProvider>(
      builder: (ctx, pb, _) {
        final title = pb.currentTrack?['title'] ?? widget.title ?? 'Unknown Title';
        final artist = pb.currentTrack?['artist'] ?? widget.artist ?? 'Unknown Artist';
        final duration = pb.durationMs;
        final imageBytes = pb.currentImageBytes;
        final imageUrl = pb.currentTrack?['imageUrl'] ?? widget.artworkUrl;

        // Синхронизируем позицию на Windows когда провайдер обновляется
        if (_isWindows && !_dragging && pb.positionMs > 0 && (pb.positionMs - _positionMs).abs() > 2000) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _positionMs = pb.positionMs);
          });
        }

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Сейчас играет',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),

                // Обложка
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  height: _isWindows
                      ? MediaQuery.of(context).size.height * 0.35
                      : MediaQuery.of(context).size.width - 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withOpacity(0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: imageBytes != null
                        ? Image.memory(imageBytes, fit: BoxFit.cover, width: double.infinity)
                        : imageUrl != null && imageUrl.isNotEmpty && !imageUrl.startsWith('data:')
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: theme.colorScheme.surfaceVariant,
                                  child: Icon(Icons.music_note, size: 96, color: theme.colorScheme.primary),
                                ),
                              )
                            : Container(
                                color: theme.colorScheme.surfaceVariant,
                                child: Icon(Icons.music_note, size: 96, color: theme.colorScheme.primary),
                              ),
                  ),
                ),
                const SizedBox(height: 20),

                // Название и артист
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        artist,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Прогресс бар
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        ),
                        child: Slider(
                          activeColor: theme.colorScheme.primary,
                          inactiveColor: theme.colorScheme.surfaceVariant,
                          value: duration > 0 ? (_positionMs / duration).clamp(0.0, 1.0) : 0.0,
                          onChangeStart: (_) => setState(() => _dragging = true),
                          onChanged: (v) => setState(() => _positionMs = (v * duration).toInt()),
                          onChangeEnd: (v) {
                            _dragging = false;
                            pb.seekTo((v * duration).toInt());
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatMs(_positionMs),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                              )),
                          Text(_formatMs(duration),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Кнопки управления
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.shuffle, color: theme.iconTheme.color),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _positionMs = 0);
                          pb.skipPrevious();
                        },
                        icon: Icon(Icons.skip_previous, color: theme.iconTheme.color, size: 36),
                      ),
                      GestureDetector(
                        onTap: () => pb.togglePlay(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: AnimatedScale(
                            scale: pb.isPlaying ? 1.08 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              pb.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: theme.colorScheme.onPrimary,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _positionMs = 0);
                          pb.skipNext();
                        },
                        icon: Icon(Icons.skip_next, color: theme.iconTheme.color, size: 36),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: Icon(Icons.repeat, color: theme.iconTheme.color),
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