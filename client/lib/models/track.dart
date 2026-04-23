class Track {
  final String id;
  final String name;
  final String artist;

  Track({required this.id, required this.name, required this.artist});

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      name: json['trackName'] as String? ?? json['name'] as String? ?? '',
      artist: json['artistName'] as String? ?? json['artist'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackName': name,
        'artistName': artist,
      };
}
