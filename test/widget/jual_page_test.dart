import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/cs/pages/jual_page.dart';

void main() {
  testWidgets('JualPage shows loading indicator when adding customer', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: const MaterialApp(
          home: JualPage(),
        ),
      ),
    );

    // Simulate adding a customer
    await tester.enterText(find.byType(TextField).first, 'John Doe');
    await tester.enterText(find.byType(TextField).at(1), '123456789');
    await tester.tap(find.byType(ElevatedButton));

    // Verify loading indicator is shown
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
