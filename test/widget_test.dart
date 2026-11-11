import 'package:flutter_test/flutter_test.dart';
import 'package:adventure_runner/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build aplikasi AdventureRunnerApp dan jalankan 1 frame
    await tester.pumpWidget(const AdventureRunnerApp());

    // Memastikan aplikasi berhasil di-render tanpa crash
    expect(find.byType(AdventureRunnerApp), findsOneWidget);
  });
}