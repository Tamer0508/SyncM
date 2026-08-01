class Friend {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? friendshipId;
  final bool isOnline;
  final DateTime? lastSeenAt;
  final bool isOnlineHidden;

  Friend({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.friendshipId, 
    this.isOnline = false, 
    this.lastSeenAt,
    this.isOnlineHidden = false});

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: json['id'] ?? json['friendId'] ?? '',
        name: json['displayName'] as String? ?? json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        friendshipId: json['friendshipId'] as String?, 
        isOnline: json['isOnline'] == true,
        // .toLocal(): сервер отдаёт время в UTC, а сравнивается оно с
        // DateTime.now() (местным). Без перевода «был в сети» показывал
        // смещение на весь часовой пояс (для UTC+5 — минус 5 часов).
        lastSeenAt: json['lastSeenAt'] != null
            ? DateTime.parse(json['lastSeenAt']).toLocal()
            : null,
        isOnlineHidden: json['isOnlineHidden'] == true,
      );
}