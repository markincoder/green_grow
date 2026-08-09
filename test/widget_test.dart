import 'package:flutter_test/flutter_test.dart';
import 'package:green_grow/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app loads home brand', (tester) async {
    await tester.pumpWidget(const GreenGrowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Микрозелень'), findsOneWidget);
    expect(find.text('Главная'), findsOneWidget);
  });
}
