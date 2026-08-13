import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/services/planting_log_service.dart';
import 'package:green_grow/models/plant.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plantings_log_');
    PlantingLogService.instance.directoryOverride = tempDir;
  });

  tearDown(() async {
    PlantingLogService.instance.directoryOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('appends planting log rows in expected format', () async {
    final at = DateTime(2026, 8, 11, 12, 40);
    await PlantingLogService.instance.append(
      at: at,
      cycleName: 'Горох от 11 авг',
      action: 'начать',
      stageOrComment: PlantingLogService.stageField(GrowthStage.soak),
    );
    await PlantingLogService.instance.append(
      at: DateTime(2026, 8, 14, 15, 40),
      cycleName: 'Горох от 11 авг',
      action: 'удалить',
      stageOrComment: '',
    );

    final file = await PlantingLogService.instance.logFile();
    expect(file, isNotNull);
    final text = await file!.readAsString();
    expect(
      text.trim().split('\n'),
      [
        '11.08.2026 12:40;Горох от 11 авг;начать;замачивание',
        '14.08.2026 15:40;Горох от 11 авг;удалить;',
      ],
    );
  });
}
