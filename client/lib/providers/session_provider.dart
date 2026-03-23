import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/session.dart';

class SessionProvider with ChangeNotifier {
  final ApiService api;

  SessionProvider({ApiService? api}) : api = api ?? ApiService();

  List<SessionModel> _sessions = [];
  List<SessionModel> get sessions => _sessions;
  bool _loading = false;
  bool get loading => _loading;

  Future<void> fetchMySessions() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await api.getMySessions();
      _sessions = data
          .map((e) => SessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> createSession(String name, String friendId) async {
    return await api.createSession(name, friendId);
  }

  Future<bool> addTracks(String sessionId, List<Map<String, dynamic>> tracks) async {
    return await api.addTracks(sessionId, tracks);
  }

  Future<bool> rateTrack(String trackId, int rating) async {
    return await api.rateTrack(trackId, rating);
  }

  Future<Map<String, dynamic>?> endSession(String sessionId) async {
    return await api.endSession(sessionId);
  }
}
