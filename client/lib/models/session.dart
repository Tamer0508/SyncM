import '../utils/app_globals.dart';

class SessionModel {
  final String id;
  final String name;
  final bool isActive;

  SessionModel({required this.id, required this.name, required this.isActive});

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? appL10n?.homeSession ?? 'Сессия',
        isActive: json['isActive'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isActive': isActive,
      };
}