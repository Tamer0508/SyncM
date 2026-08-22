class User {
  final String id;

  final String? publicId;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final String? customAvatarUrl;
  final bool spotifyConnected;
  final String? spotifyId;
  final bool isFriendsHidden;


  final bool isSearchHidden;
  final bool isActivityHidden;
  final bool isOnlineHidden;

  const User({
    required this.id,
    this.publicId,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.customAvatarUrl,
    this.spotifyConnected = false,
    this.spotifyId,
    this.isFriendsHidden = false,

    this.isSearchHidden = false,
    this.isActivityHidden = false,
    this.isOnlineHidden = false,
  });

  User copyWith({
    String? id,
    String? publicId,
    String? displayName,
    String? email,
    String? avatarUrl,
    String? customAvatarUrl,
    bool? spotifyConnected,
    String? spotifyId,
    bool? isFriendsHidden,

    bool? isSearchHidden,
    bool? isActivityHidden,
    bool? isOnlineHidden,
  }) {
    return User(
      id: id ?? this.id,
      publicId: publicId ?? this.publicId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      customAvatarUrl: customAvatarUrl ?? this.customAvatarUrl,
      spotifyConnected: spotifyConnected ?? this.spotifyConnected,
      spotifyId: spotifyId ?? this.spotifyId,
      isFriendsHidden: isFriendsHidden ?? this.isFriendsHidden,

      isSearchHidden: isSearchHidden ?? this.isSearchHidden,
      isActivityHidden: isActivityHidden ?? this.isActivityHidden,
      isOnlineHidden: isOnlineHidden ?? this.isOnlineHidden,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      publicId: json['publicId'] as String?,
      displayName: json['displayName'] as String? ?? 'Без имени',
      email: json['email'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      customAvatarUrl: json['customAvatarUrl'] as String?,
      spotifyConnected: (json['spotifyConnected'] == true) ||
          (json['spotifyLinked'] == true) ||
          ((json['spotifyId'] as String?)?.isNotEmpty ?? false),
      spotifyId: json['spotifyId'] as String?,
      isFriendsHidden: json['isFriendsHidden'] == true,

      isSearchHidden: json['isSearchHidden'] == true,
      isActivityHidden: json['isActivityHidden'] == true,
      isOnlineHidden: json['isOnlineHidden'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'displayName': displayName,
        'email': email,
        'avatarUrl': avatarUrl,
        'customAvatarUrl': customAvatarUrl,
        'spotifyConnected': spotifyConnected,
        'spotifyId': spotifyId,
        'isFriendsHidden': isFriendsHidden,
        'isSearchHidden': isSearchHidden,
        'isActivityHidden': isActivityHidden,
        'isOnlineHidden': isOnlineHidden,
      };

  String? get effectiveAvatarUrl {
    if (customAvatarUrl != null && customAvatarUrl!.isNotEmpty) return customAvatarUrl;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) return avatarUrl;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          other.id == id &&
          other.displayName == displayName &&
          other.email == email &&
          other.avatarUrl == avatarUrl &&
          other.customAvatarUrl == customAvatarUrl &&
          other.spotifyConnected == spotifyConnected &&
          other.spotifyId == spotifyId &&
          other.isFriendsHidden == isFriendsHidden &&
          other.isActivityHidden == isActivityHidden &&
          other.isOnlineHidden == isOnlineHidden &&
          other.isSearchHidden == isSearchHidden;

  @override
  int get hashCode => Object.hash(
        id,
        displayName,
        email,
        avatarUrl,
        customAvatarUrl,
        spotifyConnected,
        spotifyId,
        isFriendsHidden,
        isActivityHidden,
        isOnlineHidden,
        isSearchHidden,
      );
}