class User {
  final String id;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final bool spotifyConnected;

  User({
    required this.id,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.spotifyConnected = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      spotifyConnected:
          (json['spotifyConnected'] == true) ||
          (json['spotifyLinked'] == true) ||
          ((json['spotifyId'] as String?)?.isNotEmpty ?? false),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'avatarUrl': avatarUrl,
        'spotifyConnected': spotifyConnected,
      };
}
