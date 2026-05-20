class User {
  final String id;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final String? customAvatarUrl; 
  final bool spotifyConnected;
  final String? spotifyId;
  final bool isFriendsHidden;
  final bool isActivityHidden;
  final bool isOnlineHidden;

  User({
    required this.id,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.customAvatarUrl,
    this.spotifyConnected = false,
    this.spotifyId,
    this.isFriendsHidden = false,
    this.isActivityHidden = false,
    this.isOnlineHidden = false,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      customAvatarUrl: json['customAvatarUrl'] as String?,
      spotifyConnected:
          (json['spotifyConnected'] == true) ||
          (json['spotifyLinked'] == true) ||
          ((json['spotifyId'] as String?)?.isNotEmpty ?? false),
      spotifyId: json['spotifyId'] as String?,
      isFriendsHidden: json['isFriendsHidden'] == true,
      isActivityHidden: json['isActivityHidden'] == true,
      isOnlineHidden: json['isOnlineHidden'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'avatarUrl': avatarUrl,
        'customAvatarUrl': customAvatarUrl,
        'spotifyConnected': spotifyConnected,
        'spotifyId': spotifyId,
        'isFriendsHidden': isFriendsHidden,
        'isActivityHidden': isActivityHidden,
        'isOnlineHidden': isOnlineHidden,
      };
}
