import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/models/culture_note_photo.dart';
import 'package:green_grow/state/plant_photos_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getLibraryPath() async => root;

  @override
  Future<String?> getExternalStoragePath() async => root;

  @override
  Future<List<String>?> getExternalCachePaths() async => [root];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [root];

  @override
  Future<String?> getDownloadsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String docs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    docs = Directory.systemTemp
        .createTempSync('culture_photos_test_')
        .path;
    PathProviderPlatform.instance = _FakePathProvider(docs);
  });

  tearDown(() {
    final dir = Directory(docs);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('default caption uses short russian date', () {
    final caption = CultureNotePhoto.defaultCaption(DateTime(2026, 9, 11));
    expect(caption, '11 сен');
  });

  test('add list update caption delete keeps sort by date', () async {
    final older = Uint8List.fromList([0xFF, 0xD8, 0x01]);
    final newer = Uint8List.fromList([0xFF, 0xD8, 0x02]);

    final a = await PlantPhotosStore.add(
      plantId: '10023',
      bytes: older,
      createdAt: DateTime(2026, 9, 1, 10),
      caption: '1 сен',
    );
    final b = await PlantPhotosStore.add(
      plantId: '10023',
      bytes: newer,
      createdAt: DateTime(2026, 9, 10, 12),
      caption: '10 сен',
    );
    expect(a, isNotNull);
    expect(b, isNotNull);

    var list = await PlantPhotosStore.listFor('10023');
    expect(list.map((p) => p.id), [b!.id, a!.id]);

    await PlantPhotosStore.updateCaption(a, 'обновлено');
    list = await PlantPhotosStore.listFor('10023');
    expect(list.firstWhere((p) => p.id == a.id).caption, 'обновлено');

    final bytes = await PlantPhotosStore.bytesFor(b);
    expect(bytes, newer);

    await PlantPhotosStore.delete(b);
    list = await PlantPhotosStore.listFor('10023');
    expect(list.map((p) => p.id), [a.id]);
  });

  test('enforces max photos per culture', () async {
    for (var i = 0; i < PlantPhotosStore.maxPerPlant; i++) {
      final photo = await PlantPhotosStore.add(
        plantId: '10005',
        bytes: Uint8List.fromList([i]),
        createdAt: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      );
      expect(photo, isNotNull);
    }
    final overflow = await PlantPhotosStore.add(
      plantId: '10005',
      bytes: Uint8List.fromList([99]),
    );
    expect(overflow, isNull);
  });
}
