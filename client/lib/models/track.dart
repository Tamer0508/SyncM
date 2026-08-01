class Track {
  final String id;
  final String name;
  final String artist;
  final int? durationMs; // длительность в миллисекундах

  Track({
    required this.id,
    required this.name,
    required this.artist,
    this.durationMs,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      // Spotify отдаёт id: null для локальных файлов и недоступных в
      // регионе треков — жёсткое приведение роняло разбор всего списка.
      id: json['id'] as String? ?? '',
      name: json['trackName'] as String? ?? json['name'] as String? ?? '',
      artist: json['artistName'] as String? ?? json['artist'] as String? ?? '',
      durationMs: json['durationMs'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackName': name,
        'artistName': artist,
        'durationMs': durationMs,
      };
}