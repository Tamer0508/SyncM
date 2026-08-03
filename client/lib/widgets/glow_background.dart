import 'package:flutter/material.dart';

class GlowBackground extends StatefulWidget {
  final Color dominantColor;
  final Color vibrantColor;
  const GlowBackground(
      {super.key, required this.dominantColor, required this.vibrantColor});
  @override
  State<GlowBackground> createState() => GlowBackgroundState();
}

class GlowBackgroundState extends State<GlowBackground>
    with TickerProviderStateMixin {
  late AnimationController _colorController;
  late Animation<Color?> _dominantAnim;
  late Animation<Color?> _vibrantAnim;
  Color _currentDominant = Colors.blueGrey.shade800;
  Color _currentVibrant = Colors.blueGrey.shade600;

  @override
  void initState() {
    super.initState();
    _colorController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _dominantAnim =
        ColorTween(begin: _currentDominant, end: widget.dominantColor)
            .animate(_colorController);
    _vibrantAnim = ColorTween(begin: _currentVibrant, end: widget.vibrantColor)
        .animate(_colorController);
    _colorController.addListener(() {
      setState(() {
        _currentDominant = _dominantAnim.value!;
        _currentVibrant = _vibrantAnim.value!;
      });
    });
    _colorController.forward();
  }

  @override
  void didUpdateWidget(covariant GlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dominantColor != widget.dominantColor ||
        oldWidget.vibrantColor != widget.vibrantColor) {
      _dominantAnim =
          ColorTween(begin: _currentDominant, end: widget.dominantColor)
              .animate(_colorController);
      _vibrantAnim =
          ColorTween(begin: _currentVibrant, end: widget.vibrantColor)
              .animate(_colorController);
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
            _currentVibrant.withValues(alpha: 0.3),
            _currentDominant.withValues(alpha: 0.2)
          ],
        ),
      ),
    );
  }
}