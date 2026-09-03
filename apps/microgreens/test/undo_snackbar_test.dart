import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/widgets/common_widgets.dart';
import 'package:green_grow/widgets/garden_stage_timeline.dart';
import 'package:green_grow/services/tray_history_store.dart';

void main() {
  testWidgets('undo snackbar auto-hides after 3s even if host is disposed',
      (tester) async {
    final host = UndoSnackBarHost();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  host.show(
                    context: context,
                    message: 'Горох от 1 сен',
                    onUndo: () async {},
                  );
                },
                child: const Text('mark'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('mark'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Горох от 1 сен'), findsOneWidget);
    expect(find.text('Отменить'), findsOneWidget);

    // Tab switch disposes HomeScreen / GardenScreen and used to cancel
    // the close timer, leaving a persistent action snackbar forever.
    host.dispose();

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Горох от 1 сен'), findsNothing);
    expect(find.text('Отменить'), findsNothing);
  });

  testWidgets('history puts stamp and action on separate lines', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GardenActionHistory(
            events: [
              TrayHistoryEvent(
                at: DateTime(2026, 9, 1, 20, 9),
                action: 'посеять',
                stage: 'проращивание',
              ),
              TrayHistoryEvent(
                at: DateTime(2026, 9, 1, 9, 25),
                action: 'старт',
                stage: 'замачивание',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('01.09.2026 20:09'), findsOneWidget);
    expect(find.text('посеять → проращивание'), findsOneWidget);
    expect(find.text('01.09.2026 09:25'), findsOneWidget);
    expect(find.text('старт → замачивание'), findsOneWidget);
    expect(
      find.text('01.09.2026 20:09 посеять → проращивание'),
      findsNothing,
    );
  });
}
