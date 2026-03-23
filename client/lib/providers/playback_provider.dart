import 'package:flutter/material.dart';

class PlaybackProvider extends ChangeNotifier {
  Map<String, dynamic>? _currentTrack;
  bool _isPlaying = false;

  Map<String, dynamic>? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;

  void playTrack(Map<String, dynamic> track) {
    _currentTrack = track;
    _isPlaying = true;
    notifyListeners();
  }

  void togglePlay() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void stop() {
    _isPlaying = false;
    _currentTrack = null;
    notifyListeners();
  }
}
