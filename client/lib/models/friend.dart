/// Состояние отношений с пользователем в результатах поиска.
///
/// Сервер возвращает это поле в /friends/search, но клиент его раньше не
/// читал: кнопка «Добавить» показывалась даже для тех, кто уже в друзьях,
/// запрос уходил впустую и возвращался отказом «Вы уже друзья».
enum FriendshipStatus {
  none,
  friends,
  /// Заявка отправлена нами и ждёт ответа.
  sent,
  /// Заявка получена от этого пользователя.
  received;

  static FriendshipStatus fromJson(Object? value) {
    return switch (value) {
      'friends' => FriendshipStatus.friends,
      'sent' => FriendshipStatus.sent,
      'received' => FriendshipStatus.received,
      _ => FriendshipStatus.none,
    };
  }
}

class Friend {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? friendshipId;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool isOnlineHidden;
  final FriendshipStatus friendshipStatus;

  const Friend({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.friendshipId,
    this.isOnline = false,
    this.lastSeenAt,
    this.isOnlineHidden = false,
    this.friendshipStatus = FriendshipStatus.none,
  });

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: (json['id'] ?? json['friendId'] ?? '') as String,
        name: json['displayName'] as String? ?? json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        friendshipId: json['friendshipId'] as String?,
        isOnline: json['isOnline'] == true,
        lastSeenAt: json['lastSeenAt'] is String
            ? DateTime.tryParse(json['lastSeenAt'] as String)?.toLocal()
            : null,
        isOnlineHidden: json['isOnlineHidden'] == true,
        friendshipStatus: FriendshipStatus.fromJson(json['friendshipStatus']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': name,
        'avatarUrl': avatarUrl,
        'friendshipId': friendshipId,
        'isOnline': isOnline,
        // ISO-8601 в UTC: fromJson переведёт обратно в местное время.
        'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
        'isOnlineHidden': isOnlineHidden,
        'friendshipStatus': friendshipStatus.name,
      };

  Friend copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? friendshipId,
    bool? isOnline,
    DateTime? lastSeenAt,
    bool? isOnlineHidden,
    FriendshipStatus? friendshipStatus,
  }) {
    return Friend(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      friendshipId: friendshipId ?? this.friendshipId,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      isOnlineHidden: isOnlineHidden ?? this.isOnlineHidden,
      friendshipStatus: friendshipStatus ?? this.friendshipStatus,
    );
  }

  /// Показывать ли статус присутствия. Учитывает настройку приватности.
  bool get showsPresence => !isOnlineHidden;
}