import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/main.dart';
import 'package:green_grow/state/access_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AccessStore.remoteEnabled = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app loads home brand', (tester) async {
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('База знаний'), findsOneWidget);
    expect(find.text('Выращивать'), findsOneWidget);
    expect(find.textContaining('Бесплатный доступ до'), findsOneWidget);
    expect(find.text('Продлить доступ'), findsOneWidget);
    expect(find.text('или введите код активации'), findsNothing);
    expect(find.byTooltip('Выращено'), findsNothing);
  });

  testWidgets('opens harvest stats from garden', (tester) async {
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Моя грядка'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Выращено'));
    await tester.pumpAndSettle();

    expect(find.text('Выращено'), findsWidgets);
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('За неделю'), findsNothing);
    expect(find.text('За месяц'), findsNothing);
    expect(find.text('Выбрать...'), findsOneWidget);
    expect(find.text('От'), findsNothing);
    expect(
      find.textContaining('Пока нет собранных лотков'),
      findsOneWidget,
    );

    await tester.tap(find.text('Выбрать...'));
    await tester.pumpAndSettle();
    expect(find.text('От'), findsOneWidget);
    expect(find.text('До'), findsOneWidget);
    expect(find.text('начало'), findsOneWidget);
    expect(find.text('сегодня'), findsOneWidget);
  });

  testWidgets('opens activation sheet from trial card', (tester) async {
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Продлить доступ'));
    await tester.pumpAndSettle();

    expect(find.text('Активировать код доступа'), findsOneWidget);
    expect(
      find.text('Введите email, на который оформляли код доступа, и сам код'),
      findsOneWidget,
    );
    expect(find.text('email@example.com'), findsOneWidget);
    expect(find.text('Код активации'), findsOneWidget);
    expect(find.text('Вставить код'), findsOneWidget);
    expect(find.textContaining('Код активации вы можете оформить на сайте'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Активировать'), findsOneWidget);
  });

  testWidgets('shows activation when trial ended', (tester) async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 8));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
    });
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Пробный период закончился'), findsOneWidget);
    expect(find.textContaining('Бесплатный доступ до'), findsOneWidget);
    expect(find.text('Активировать код доступа'), findsOneWidget);
    expect(find.text('Главная'), findsNothing);
  });

  testWidgets('shows paid access until date without activate', (tester) async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 30));
    final paid = DateTime.utc(2027, 8, 14);
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': paid.toIso8601String(),
    });
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.textContaining('Доступ активирован до'), findsOneWidget);
    expect(find.textContaining('Бесплатный доступ до'), findsNothing);
    expect(find.textContaining('Пробная бесплатная версия до'), findsNothing);
    expect(find.text('Активировать доступ'), findsNothing);
    expect(find.text('Продлить доступ'), findsNothing);
    expect(find.text('Главная'), findsOneWidget);
  });

  testWidgets('shows activate again when paid access ended', (tester) async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 400));
    final paid = DateTime.now().toUtc().subtract(const Duration(days: 1));
    SharedPreferences.setMockInitialValues({
      'access_first_start_at': started.toIso8601String(),
      'access_paid_expires_at': paid.toIso8601String(),
    });
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Срок доступа закончился'), findsOneWidget);
    expect(find.textContaining('Доступ действовал до'), findsOneWidget);
    expect(find.text('Активировать код доступа'), findsOneWidget);
    expect(find.textContaining('Доступ активирован до'), findsNothing);
    expect(find.text('Главная'), findsNothing);
  });
}
