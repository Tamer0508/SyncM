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
        lastSeenAt: json['lastSeenAt'] != null ? DateTime.parse(json['lastSeenAt']) : null,
        isOnlineHidden: json['isOnlineHidden'] == true,
      );
}