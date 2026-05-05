class User {
  final String id;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final bool spotifyConnected;
  final String? spotifyId;

  User({
    required this.id,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.spotifyConnected = false,
    this.spotifyId,
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
      spotifyId: json['spotifyId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'avatarUrl': avatarUrl,
        'spotifyConnected': spotifyConnected,
        'spotifyId': spotifyId,
      };
}
