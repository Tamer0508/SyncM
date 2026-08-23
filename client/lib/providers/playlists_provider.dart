import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../utils/local_store.dart';

class PlaylistsProvider with ChangeNotifier {
  PlaylistsProvider({ApiService? api}) : api = api ?? ApiService() {
    _restoreFromCache();
  }

  final ApiService api;

  void syncCookie(String cookie) => api.setCookie(cookie);

  List<Map<String, dynamic>> _custom = const [];
  List<Map<String, dynamic>> _spotify = const [];

  bool _loadingCustom = false;
  bool _loadingSpotify = false;
  bool _spotifyUnavailable = false;

  List<Map<String, dynamic>> get custom => UnmodifiableListView(_custom);

  List<Map<String, dynamic>> get spotify => UnmodifiableListView(_spotify);

  bool get loadingCustom => _loadingCustom;
  bool get loadingSpotify => _loadingSpotify;

  bool get spotifyUnavailable => _spotifyUnavailable;

  void _restoreFromCache() {
    _custom = LocalStore.readList(StoreKeys.customPlaylists);
    _spotify = LocalStore.readList(StoreKeys.spotifyPlaylists);
  }

  Map<String, dynamic>? byId(String playlistId) {
    for (final playlist in _custom) {
      if (playlist['id'] == playlistId) return playlist;
    }
    for (final playlist in _spotify) {
      if (playlist['id'] == playlistId) return playlist;
    }
    return null;
  }


  Future<void> loadAll({bool refresh = false}) async {
    await Future.wait([
      loadCustom(refresh: refresh),
      loadSpotify(refresh: refresh),
    ]);
  }

  Future<void> loadCustom({bool refresh = false}) async {
    _loadingCustom = true;
    notifyListeners();
    try {
      final list = await api.getMyPlaylists(refresh: refresh);
      _custom = _normalize(list);
      unawaited(LocalStore.saveList(StoreKeys.customPlaylists, _custom));
    } finally {
      _loadingCustom = false;
      notifyListeners();
    }
  }

  Future<void> loadSpotify({bool refresh = false}) async {
    _loadingSpotify = true;
    notifyListeners();
    try {
      final list = await api.getPlaylists(refresh: refresh);
      _spotify = _normalize(list);
      _spotifyUnavailable = false;
      unawaited(LocalStore.saveList(StoreKeys.spotifyPlaylists, _spotify));
    } on ApiException catch (err) {
      if (err.statusCode == 409) {
        _spotify = const [];
        _spotifyUnavailable = true;
        unawaited(LocalStore.remove(StoreKeys.spotifyPlaylists));
        return;
      }
      rethrow;
    } finally {
      _loadingSpotify = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> _normalize(List<dynamic> raw) =>
      raw.whereType<Map>().map(Map<String, dynamic>.from).toList();


  Future<Map<String, dynamic>> create(String name, {String? description}) async {
    final created = await api.createCustomPlaylist(name, description: description);
    await loadCustom(refresh: true);
    return created;
  }

  Future<void> rename(String playlistId, String name) =>
      _update(playlistId, () => api.updatePlaylist(playlistId, name: name));

  Future<void> edit(
    String playlistId, {
    String? name,
    String? description,
    bool clearDescription = false,
  }) =>
      _update(
        playlistId,
        () => api.updatePlaylist(
          playlistId,
          name: name,
          description: description,
          clearDescription: clearDescription,
        ),
      );

  Future<void> setCover(String playlistId, Uint8List bytes, String fileName) =>
      _update(playlistId, () => api.uploadPlaylistCover(playlistId, bytes, fileName));

  Future<void> removeCover(String playlistId) =>
      _update(playlistId, () => api.deletePlaylistCover(playlistId));

  Future<Map<String, dynamic>> duplicate(String playlistId, {String? name}) async {
    final copy = await api.duplicatePlaylist(playlistId, name: name);
    await loadCustom(refresh: true);
    return copy;
  }

  Future<void> delete(String playlistId) async {
    final previous = _custom;
    _custom = _custom.where((p) => p['id'] != playlistId).toList();
    notifyListeners();

    try {
      await api.deletePlaylist(playlistId);
    } catch (_) {
      _custom = previous;
      notifyListeners();
      rethrow;
    }

    await loadCustom(refresh: true);
  }

  Future<void> _update(
    String playlistId,
    Future<Map<String, dynamic>> Function() request,
  ) async {
    final updated = await request();
    _applyLocal(playlistId, updated);
    await loadCustom(refresh: true);
  }

  void _applyLocal(String playlistId, Map<String, dynamic> updated) {
    final index = _custom.indexWhere((p) => p['id'] == playlistId);
    if (index == -1) return;
    final next = List<Map<String, dynamic>>.from(_custom);
    next[index] = {...next[index], ...updated};
    _custom = next;
    notifyListeners();
  }

  Future<({int added, int skipped})> addTracks(
    String playlistId,
    List<Map<String, dynamic>> tracks,
  ) async {
    if (tracks.isEmpty) return (added: 0, skipped: 0);

    var added = 0;
    var skipped = 0;

    const chunkSize = 100;
    for (var i = 0; i < tracks.length; i += chunkSize) {
      final end = (i + chunkSize < tracks.length) ? i + chunkSize : tracks.length;
      final result = await api.addTracksToPlaylist(playlistId, tracks.sublist(i, end));
      added += result.added;
      skipped += result.skipped;
    }

    if (added > 0) await loadCustom(refresh: true);
    return (added: added, skipped: skipped);
  }

  Future<void> removeTrack(String playlistId, String trackUri) async {
    await api.removeTrackFromPlaylist(playlistId, trackUri);
    await loadCustom(refresh: true);
  }

  Future<void> clearTracks(String playlistId) async {
    await api.clearPlaylist(playlistId);
    await loadCustom(refresh: true);
  }

  Future<void> reorderTracks(String playlistId, List<String> trackUris) =>
      api.reorderPlaylistTracks(playlistId, trackUris);

  Future<List<Map<String, dynamic>>?> tracksOf(
    String playlistId, {
    required bool isCustom,
    bool refresh = false,
  }) async {
    if (isCustom) {
      final raw = await api.getPlaylistTracksById(playlistId, refresh: refresh);
      return raw == null ? null : _normalize(raw);
    }

    try {
      return _normalize(await api.getPlaylistTracks(playlistId, refresh: refresh));
    } on ApiException catch (err) {
      if (err.statusCode == 403 || err.statusCode == 500) return null;
      rethrow;
    }
  }

  void reset() {
    _custom = const [];
    _spotify = const [];
    _spotifyUnavailable = false;
    notifyListeners();
  }
}

extension PlaylistFields on Map<String, dynamic> {
  String get playlistId => this['id'] as String? ?? '';
  String get playlistName => this['name'] as String? ?? 'Без названия';
  String get playlistDescription => this['description'] as String? ?? '';
  String? get playlistImageUrl {
    final url = this['imageUrl'] as String?;
    return (url == null || url.isEmpty) ? null : url;
  }

  int get playlistTrackCount => (this['trackCount'] as num?)?.toInt() ?? 0;

  bool get isCustomPlaylist => this['isCustom'] == true;
}
