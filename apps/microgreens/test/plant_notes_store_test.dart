import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/state/plant_notes_store.dart';
import 'package:green_grow/widgets/culture_notes_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and loads a note per culture', () async {
    await PlantNotesStore.setNote('10023', 'Сорт Лакомка');
    expect(await PlantNotesStore.noteFor('10023'), 'Сорт Лакомка');
    expect(await PlantNotesStore.noteFor('10024'), '');
  });

  test('empty note removes the culture key', () async {
    await PlantNotesStore.setNote('10023', 'черновик');
    await PlantNotesStore.setNote('10023', '   ');
    expect(await PlantNotesStore.noteFor('10023'), '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PlantNotesStore.storageKey), isNull);
  });

  test('reads a note saved under a legacy plant id', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      PlantNotesStore.storageKey,
      jsonEncode({'sunflower': 'Прижим 2 кг'}),
    );
    expect(await PlantNotesStore.noteFor('10023'), 'Прижим 2 кг');
    await PlantNotesStore.setNote('10023', 'Прижим 2 кг');
    expect(
      jsonDecode(prefs.getString(PlantNotesStore.storageKey)!),
      {'10023': 'Прижим 2 кг'},
    );
  });

  testWidgets('notes field shows saved text and persists edits', (tester) async {
    await PlantNotesStore.setNote('10023', 'Сорт Лакомка');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CultureNotesField(plantId: '10023'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('Заметки'), findsOneWidget);
    expect(find.text('Сорт Лакомка'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Новая заметка');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(await PlantNotesStore.noteFor('10023'), 'Новая заметка');
  });
}
