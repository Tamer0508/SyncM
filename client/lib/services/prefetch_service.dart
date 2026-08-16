import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../providers/friends_provider.dart';
import '../providers/session_provider.dart';
import '../services/api_service.dart';

class PrefetchService {
  PrefetchService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;

  bool _inProgress = false;
  DateTime? _lastRun;

  /// Не чаще раза в полминуты: прогрев может дёрнуться и при входе, и при
  /// возврате приложения из фона, а гонять одни и те же запросы подряд
  /// незачем — они лишь съедают лимит частоты на сервере.
  static const _minInterval = Duration(seconds: 30);

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
      // Параллельно, а не по очереди: запросы независимы, и последовательное
      // выполнение растянуло бы прогрев на сумму задержек сети.
      await Future.wait([
        _safe(() => friends.fetchFriends(refresh: true)),
        _safe(() => friends.fetchIncomingRequests(refresh: true)),
        _safe(() => sessions.fetchMySessions()),
        _safe(() => sessions.fetchInvites()),
        // Плейлисты греем ради кэша на сервере и в ApiService: результат
        // здесь не нужен, экран запросит его сам и получит уже готовый.
        _safe(() async => _api.getMyPlaylists()),
        _safe(() async => _api.getPlaylists()),
      ]);

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
        .take(30) // разумный предел: греть сотни изображений незачем
        .toList();

    for (final url in urls) {
      if (!context.mounted) return;
      await _safe(() => precacheImage(CachedNetworkImageProvider(url), context));
    }
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (err) {
      debugPrint('Prefetch step failed (ignored): $err');
    }
  }
}