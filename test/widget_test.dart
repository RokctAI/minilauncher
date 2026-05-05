import 'package:flutter_test/flutter_test.dart';
import 'package:minimal_launcher/main.dart';

void main() {
  testWidgets('Launcher smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MinimalLauncher());

    // Verify that it starts with a loading indicator or at least builds
    expect(find.byType(MinimalLauncher), findsOneWidget);
  });
}
