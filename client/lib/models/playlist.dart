class Playlist {
  final String id;
  final String name;

  Playlist({required this.id, required this.name});

  factory Playlist.fromJson(Map<String, dynamic> json) =>
      Playlist(id: json['id'] as String, name: json['name'] as String);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };
}
