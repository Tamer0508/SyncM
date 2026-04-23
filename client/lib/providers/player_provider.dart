import 'package:flutter/material.dart';

class PlayerProvider with ChangeNotifier {
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  void togglePlay() {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }
}
