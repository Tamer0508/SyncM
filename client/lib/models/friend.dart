class Friend {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? friendshipId; 

  Friend({required this.id, required this.name, this.avatarUrl, this.friendshipId});

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: json['id'] as String,
        name: json['displayName'] as String? ?? json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
        friendshipId: json['friendshipId'] as String?, 
      );
}