import '../models/plant.dart';

/// User photo attached to a knowledge-base culture note.
class CultureNotePhoto {
  const CultureNotePhoto({
    required this.id,
    required this.plantId,
    required this.createdAt,
    required this.caption,
  });

  final String id;
  final String plantId;
  final DateTime createdAt;
  final String caption;

  CultureNotePhoto copyWith({String? caption}) => CultureNotePhoto(
        id: id,
        plantId: plantId,
        createdAt: createdAt,
        caption: caption ?? this.caption,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plantId': plantId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'caption': caption,
      };

  factory CultureNotePhoto.fromJson(Map<String, dynamic> json) {
    return CultureNotePhoto(
      id: json['id'] as String,
      plantId: json['plantId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      caption: (json['caption'] as String?)?.trim().isNotEmpty == true
          ? json['caption'] as String
          : defaultCaption(DateTime.now()),
    );
  }

  /// Default caption: `11 сен` (same style as tray dates).
  static String defaultCaption([DateTime? at]) =>
      formatStartDate(at ?? DateTime.now()).replaceAll('.', '');
}
