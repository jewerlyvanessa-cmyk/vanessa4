// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/main.dart' as main_app;
import 'package:vanessa3/core/state/user_state.dart' as core_state;
import 'package:vanessa3/core/theme/app_theme.dart';
import 'package:vanessa3/routes/app_routes.dart' as app_routes;
import 'package:vanessa3/modules/cs/pages/jual_page.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const main_app.VanessaApp());

    // Verify that our counter starts at 0.
    expect(find.text('Counter: 0'), findsOneWidget); // Ensure text matches actual app UI
    expect(find.text('Counter: 1'), findsNothing);

    // Tap the '+' icon and trigger a frame.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify that our counter has incremented.
    expect(find.text('Counter: 0'), findsNothing);
    expect(find.text('Counter: 1'), findsOneWidget);
  });

  group('Order Flow Tests', () {
    testWidgets('Create new order', (WidgetTester tester) async {
      // Use the mock client directly in the test
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/customers') {
          if (request.method == 'GET') {
            return http.Response(
              '{"data": [{"id": 1, "name": "Jane Doe", "phone": "9876543210"}]}',
              200,
            );
          } else if (request.method == 'POST') {
            return http.Response(
              '{"data": {"customer_id": 1, "name": "Jane Doe", "phone": "9876543210"}}',
              201,
            );
          }
        }
        return http.Response('Not Found', 404);
      });

      // Pass the mock client to the widget being tested
      await tester.pumpWidget(
        MaterialApp(
          home: JualPage(client: mockClient),
        ),
      );

      // Verify the page title is rendered
      expect(find.text('Form Order Jual'), findsOneWidget);

      // Verify the customer input field is rendered
      expect(find.byKey(const Key('customerField')), findsOneWidget);

      // Add a delay to ensure data is loaded before interacting with the field
      await tester.pumpAndSettle(const Duration(seconds: 2)); // Ensure field is ready for interaction

      // Simulate adding a new customer
      await tester.enterText(find.byKey(const Key('customerField')), 'Jane Doe');
      await tester.tap(find.widgetWithText(IconButton, 'Tambah Customer Baru'));
      await tester.pumpAndSettle();

      // Verify the customer was added successfully
      expect(find.text('Customer berhasil ditambahkan'), findsOneWidget);
    });

    testWidgets('Order Form Test', (WidgetTester tester) async {
      // Build the app and navigate to the order form page
      await tester.pumpWidget(const main_app.VanessaApp());

      // Simulate navigation to the order form
      expect(find.text('Order Management'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Order'));
      await tester.pumpAndSettle();

      // Verify the order form is displayed
      expect(find.text('Form Order Jual'), findsOneWidget);

      // Fill out the customer field
      await tester.enterText(find.byKey(const Key('customerField')), 'Jane Doe');
      await tester.pump();

      // Submit the form
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      // Verify the order was created successfully
      expect(find.text('Order Created Successfully'), findsOneWidget);
    });
  });

  group('Payment Flow Tests', () {
    testWidgets('Process payment', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Simulate payment process
      expect(find.text('Payment Processing'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Pay Now'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Pay Now'));
      await tester.pumpAndSettle();

      // Verify payment success
      expect(find.text('Payment Successful'), findsOneWidget);
    });
  });

  group('Workshop Flow Tests', () {
    testWidgets('Complete workshop task', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Simulate workshop task completion
      expect(find.text('Workshop Tasks'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Complete Task'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Task'));
      await tester.pumpAndSettle();

      // Verify task completion
      expect(find.text('Task Completed Successfully'), findsOneWidget);
    });
  });

  group('Reporting Flow Tests', () {
    testWidgets('Generate report', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Simulate report generation
      expect(find.text('Reporting & Analytics'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Generate Report'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Generate Report'));
      await tester.pumpAndSettle();

      // Verify report generation
      expect(find.text('Report Generated Successfully'), findsOneWidget);
    });
  });

  group('Login Flow Tests', () {
    testWidgets('Login flow test', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Verify the login screen is displayed
      expect(find.widgetWithText(AppBar, 'Login'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Enter credentials and tap login
      await tester.enterText(find.byType(TextFormField).at(0), 'testuser');
      await tester.enterText(find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
      await tester.pumpAndSettle();

      // Verify navigation to dashboard
      expect(find.text('Welcome to Dashboard'), findsOneWidget);
    });
  });

  group('Dashboard Flow Tests', () {
    testWidgets('Dashboard flow test for cs role', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            main_app.userStateProvider.overrideWith((ref) => core_state.UserStateNotifier()),
          ],
          child: MaterialApp(
            title: 'Vanessa App',
            theme: AppTheme.lightTheme,
            initialRoute: app_routes.AppRoutes.dashboard,
            routes: app_routes.AppRoutes.routes,
          ),
        ),
      );

      // Verify the dashboard screen for cs role
      expect(find.text('Welcome, cs!'), findsOneWidget);
      expect(find.text('Manage Orders'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
    });
  });

  group('ScanQRUploadPhotoPage Tests', () {
    testWidgets('Upload photo functionality', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Navigate to ScanQRUploadPhotoPage
      await tester.tap(find.widgetWithText(ElevatedButton, 'Scan QR / Upload Photo'));
      await tester.pumpAndSettle();

      // Verify the page is displayed
      expect(find.text('Scan QR / Upload Photo'), findsOneWidget);

      // Simulate photo upload
      await tester.tap(find.widgetWithText(ElevatedButton, 'Upload Photo'));
      await tester.pumpAndSettle();

      // Verify photo upload success
      expect(find.text('Photo Uploaded Successfully'), findsOneWidget);
    });
  });

  group('ManualInputItemPage Tests', () {
    testWidgets('Manual item input functionality', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Navigate to ManualInputItemPage
      await tester.tap(find.widgetWithText(ElevatedButton, 'Manual Input Item'));
      await tester.pumpAndSettle();

      // Verify the page is displayed
      expect(find.text('Manual Input Item'), findsOneWidget);

      // Simulate item input
      await tester.enterText(find.byType(TextFormField).at(0), 'Item Name');
      await tester.enterText(find.byType(TextFormField).at(1), '10');
      await tester.enterText(find.byType(TextFormField).at(2), 'Gold');
      await tester.enterText(find.byType(TextFormField).at(3), '99.9');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Item'));
      await tester.pumpAndSettle();

      // Verify item save success
      expect(find.text('Item Saved Successfully'), findsOneWidget);
    });
  });

  group('WorkshopPage Tests', () {
    testWidgets('Workshop task management', (WidgetTester tester) async {
      await tester.pumpWidget(const main_app.VanessaApp());

      // Navigate to WorkshopPage
      await tester.tap(find.widgetWithText(ElevatedButton, 'Workshop'));
      await tester.pumpAndSettle();

      // Verify the page is displayed
      expect(find.text('Workshop Orders'), findsOneWidget);

      // Simulate task completion
      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Task'));
      await tester.pumpAndSettle();

      // Verify task completion success
      expect(find.text('Task Completed Successfully'), findsOneWidget);
    });
  });

  group('JualPage Tests', () {
    testWidgets('Customer input field and add button functionality', (WidgetTester tester) async {
      // Mock HTTP client
      final mockClient = MockClient((request) async {
        debugPrint('MockClient received request: \\nURL: \\${request.url}\\nMethod: \\${request.method}\\nBody: \\${request.body}');
        if (request.url.toString() == 'http://localhost:3000/api/customers') {
          return http.Response(
            '{"data": [{"customer_id": 1, "name": "John Doe", "phone": "1234567890"}]}',
            200,
          );
        } else if (request.url.toString() == 'http://10.0.2.2:3000/customers') {
          return http.Response(
            '{"data": {"customer_id": 2, "name": "Jane Doe", "phone": "9876543210"}}',
            201,
          );
        }
        return http.Response('Not Found', 404);
      });

      // Build the widget with the mocked client
      await tester.pumpWidget(
        MaterialApp(
          home: JualPage(client: mockClient),
        ),
      );

      // Wait for the widget to rebuild after fetching data
      await tester.pumpAndSettle();

      // Verify the customer input field is rendered
      expect(find.byKey(const Key('customerField')), findsOneWidget);

      // Simulate adding a new customer
      await tester.enterText(find.byKey(const Key('customerField')), 'Jane Doe');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.person_add));
      await tester.pumpAndSettle();

      // Verify the customer was added successfully
      expect(find.text('Customer berhasil ditambahkan'), findsOneWidget);
    });

    testWidgets('Customer input field interaction', (WidgetTester tester) async {
      // Mock HTTP client
      final mockClient = MockClient((request) async {
        return http.Response('{"data": []}', 200);
      });

      // Build the widget with the mocked client
      await tester.pumpWidget(
        MaterialApp(
          home: JualPage(client: mockClient),
        ),
      );

      // Wait for the widget to rebuild after fetching data
      await tester.pumpAndSettle();

      // Simulate user input in the customer field
      await tester.enterText(find.byKey(const Key('customerField')), 'New Customer');
      await tester.pumpAndSettle();

      // Verify the IconButton is now rendered
      expect(find.byIcon(Icons.person_add), findsOneWidget);
    });
  });
}
