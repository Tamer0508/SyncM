
String formatDuration(int milliseconds) {
  final totalSeconds = (milliseconds < 0 ? 0 : milliseconds) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final ss = seconds.toString().padLeft(2, '0');
  if (hours == 0) return '$minutes:$ss';

  return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
}
