import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/friend.dart';
import '../providers/friends_provider.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';
import '../utils/artwork_color_store.dart';
import '../utils/image_cache.dart';

class PrefetchService {
  PrefetchService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  bool _inProgress = false;
  DateTime? _lastRun;

  /// Не чаще раза в полминуты: прогрев может дёрнуться и при входе, и при
  /// возврате приложения из фона, а гонять одни и те же запросы подряд
  /// незачем — они лишь съедают лимит частоты на сервере.
  static const _minInterval = Duration(seconds: 30);

  static const _avatarLimit = 16;
  static const _avatarConcurrency = 3;

  /// Запускает прогрев. Не бросает исключений: это фоновая работа, и её сбой
  /// не должен ничего ломать — экраны в любом случае загрузят своё сами.
  Future<void> warmUp({
    required FriendsProvider friends,
    required SessionProvider sessions,
    bool force = false,
  }) async {
    if (_inProgress) return;
    final last = _lastRun;
    if (!force && last != null && DateTime.now().difference(last) < _minInterval) {
      return;
    }

    _inProgress = true;
    try {
      await Future.wait([
        _safe(() => sessions.fetchMySessions()),
        _safe(() => sessions.fetchInvites()),
      ]);

      // P1.
      await Future.wait([
        _safe(() => friends.fetchFriends(refresh: true)),
        _safe(() => friends.fetchIncomingRequests(refresh: true)),
      ]);

      unawaited(SchedulerBinding.instance.scheduleTask<void>(
        () {
          _safe(() async => _api.getMyPlaylists()).ignore();
          _safe(() async => _api.getPlaylists()).ignore();
        },
        Priority.idle,
      ));

      _lastRun = DateTime.now();
    } finally {
      _inProgress = false;
    }
  }

  Future<void> warmUpAvatars(BuildContext context, List<Friend> friends) async {
    final urls = friends
        .map((f) => f.avatarUrl)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .take(_avatarLimit)
        .toList();

    if (urls.isEmpty) return;

    for (var i = 0; i < urls.length; i += _avatarConcurrency) {
      if (!context.mounted) return;

      final chunk = urls.skip(i).take(_avatarConcurrency);
      await Future.wait([
        for (final url in chunk) AppImageCache.precache(url, context),
      ]);
    }

    ArtworkColorStore.warmUp(urls);
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (err) {
      debugPrint('Prefetch step failed (ignored): $err');
    }
  }
}
