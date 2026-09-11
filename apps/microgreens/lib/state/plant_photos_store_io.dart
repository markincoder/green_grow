import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/culture_note_photo.dart';
import 'plant_notes_store.dart';
import 'plant_photos_store.dart';

final _random = Random();

String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';

Future<List<CultureNotePhoto>> listForImpl(String plantId) async {
  final all = await _readMeta();
  final canonical = PlantNotesStore.canonicalPlantId(plantId);
  final list = all[canonical] ?? const <CultureNotePhoto>[];
  final sorted = [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted;
}

Future<Uint8List?> bytesForImpl(CultureNotePhoto photo) async {
  final file = await _fileFor(photo);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<CultureNotePhoto?> addImpl({
  required String plantId,
  required Uint8List bytes,
  String? caption,
  DateTime? createdAt,
}) async {
  final canonical = PlantNotesStore.canonicalPlantId(plantId);
  final all = await _readMeta();
  final current = [...(all[canonical] ?? const <CultureNotePhoto>[])];
  if (current.length >= PlantPhotosStore.maxPerPlant) return null;

  final now = createdAt ?? DateTime.now();
  final photo = CultureNotePhoto(
    id: _newId(),
    plantId: canonical,
    createdAt: now,
    caption: (caption ?? CultureNotePhoto.defaultCaption(now)).trim(),
  );

  final file = await _fileFor(photo);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);

  current.add(photo);
  all[canonical] = current;
  await _writeMeta(all);
  return photo;
}

Future<void> updateCaptionImpl(CultureNotePhoto photo, String caption) async {
  final all = await _readMeta();
  final canonical = PlantNotesStore.canonicalPlantId(photo.plantId);
  final list = [...(all[canonical] ?? const <CultureNotePhoto>[])];
  final i = list.indexWhere((p) => p.id == photo.id);
  if (i < 0) return;
  list[i] = list[i].copyWith(caption: caption.trim());
  all[canonical] = list;
  await _writeMeta(all);
}

Future<void> deleteImpl(CultureNotePhoto photo) async {
  final file = await _fileFor(photo);
  if (await file.exists()) {
    await file.delete();
  }
  final all = await _readMeta();
  final canonical = PlantNotesStore.canonicalPlantId(photo.plantId);
  final list = [...(all[canonical] ?? const <CultureNotePhoto>[])]
    ..removeWhere((p) => p.id == photo.id);
  if (list.isEmpty) {
    all.remove(canonical);
  } else {
    all[canonical] = list;
  }
  await _writeMeta(all);
}

Future<File> _fileFor(CultureNotePhoto photo) async {
  final root = await getApplicationDocumentsDirectory();
  final canonical = PlantNotesStore.canonicalPlantId(photo.plantId);
  return File(
    '${root.path}/culture_note_photos/$canonical/${photo.id}.jpg',
  );
}

Future<Map<String, List<CultureNotePhoto>>> _readMeta() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(PlantPhotosStore.metaKey);
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    final out = <String, List<CultureNotePhoto>>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! List) continue;
      final plantId = entry.key as String;
      final photos = <CultureNotePhoto>[];
      for (final item in entry.value as List) {
        if (item is! Map) continue;
        photos.add(
          CultureNotePhoto.fromJson(Map<String, dynamic>.from(item)),
        );
      }
      if (photos.isNotEmpty) out[plantId] = photos;
    }
    return out;
  } catch (_) {
    return {};
  }
}

Future<void> _writeMeta(Map<String, List<CultureNotePhoto>> all) async {
  final prefs = await SharedPreferences.getInstance();
  if (all.isEmpty) {
    await prefs.remove(PlantPhotosStore.metaKey);
    return;
  }
  final encoded = {
    for (final e in all.entries)
      e.key: e.value.map((p) => p.toJson()).toList(),
  };
  await prefs.setString(PlantPhotosStore.metaKey, jsonEncode(encoded));
}
