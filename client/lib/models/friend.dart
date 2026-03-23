class Friend {
  final String id;
  final String name;
  final String? avatarUrl;

  Friend({required this.id, required this.name, this.avatarUrl});

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: json['id'] as String,
        name: json['displayName'] as String? ?? json['name'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': name,
        'avatarUrl': avatarUrl,
      };
}
