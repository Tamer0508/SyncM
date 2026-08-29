import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../utils/notifications.dart';

class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({
    super.key,
    required this.imageBytes,
    this.title,
    this.hint,
  });

  final Uint8List imageBytes;

  final String? title;
  final String? hint;

  static const int outputSize = 512;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  late final CropController _controller;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _controller = CropController(
      aspectRatio: 1,
      defaultCrop: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _processing = true);
    final noImageDataMessage = L.of(context).cropNoImageData;
    try {
      final cropped = await _controller.croppedBitmap();
      final byteData = await cropped.toByteData(format: ImageByteFormat.png);
      if (byteData == null) throw StateError(noImageDataMessage);

      final raw = byteData.buffer.asUint8List();
      final resized = _resize(raw, AvatarCropScreen.outputSize);

      if (!mounted) return;
      Navigator.of(context).pop(resized);
    } catch (err) {
      if (!mounted) return;
      setState(() => _processing = false);
      showAppNotification(
        context,
        message: L.of(context).cropFailed,
        type: NotificationType.error,
      );
    }
  }

  Uint8List _resize(Uint8List source, int size) {
    final decoded = img.decodeImage(source);
    if (decoded == null) return source;
    if (decoded.width <= size && decoded.height <= size) return source;

    final resized = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodePng(resized, level: 6));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? L.of(context).cropTitle),
        actions: [
          TextButton(
            onPressed: _processing ? null : _apply,
            child: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(L.of(context).cropDone, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: CropImage(
                controller: _controller,
                image: Image.memory(widget.imageBytes),
                gridColor: Colors.white70,
                gridCornerSize: 28,
                gridThinWidth: 1,
                gridThickWidth: 4,
                scrimColor: Colors.black.withValues(alpha: 0.55),
                alwaysShowThirdLines: true,
                minimumImageSize: 64,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  Text(
                    widget.hint ?? L.of(context).cropHint,
                    textAlign: TextAlign.center,
                    style: context.texts.bodySmall?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _processing
                            ? null
                            : () => _controller.rotateLeft(),
                        icon: const Icon(Icons.rotate_left_rounded, color: Colors.white),
                        label: Text(L.of(context).cropRotateLeft, style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      TextButton.icon(
                        onPressed: _processing
                            ? null
                            : () => _controller.rotateRight(),
                        icon: const Icon(Icons.rotate_right_rounded, color: Colors.white),
                        label: Text(L.of(context).cropRotateRight, style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}