import 'dart:typed_data';

import '../models/culture_note_photo.dart';
import 'plant_photos_store_io.dart'
    if (dart.library.html) 'plant_photos_store_web.dart' as impl;

/// Local photos for culture notes (files on Android, IndexedDB on web).
class PlantPhotosStore {
  PlantPhotosStore._();

  static const maxPerPlant = 30;
  static const metaKey = 'plant_photos_meta_v1';

  static Future<List<CultureNotePhoto>> listFor(String plantId) =>
      impl.listForImpl(plantId);

  static Future<Uint8List?> bytesFor(CultureNotePhoto photo) =>
      impl.bytesForImpl(photo);

  /// Adds a JPEG (already compressed by picker). Returns null if over limit.
  static Future<CultureNotePhoto?> add({
    required String plantId,
    required Uint8List bytes,
    String? caption,
    DateTime? createdAt,
  }) =>
      impl.addImpl(
        plantId: plantId,
        bytes: bytes,
        caption: caption,
        createdAt: createdAt,
      );

  static Future<void> updateCaption(CultureNotePhoto photo, String caption) =>
      impl.updateCaptionImpl(photo, caption);

  static Future<void> delete(CultureNotePhoto photo) =>
      impl.deleteImpl(photo);
}
