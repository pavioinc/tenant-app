import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivasaos_tenant_app/core/url_opener.dart';
import 'package:nivasaos_tenant_app/features/profile/app_feedback_screen.dart';
import 'package:nivasaos_tenant_app/theme/nivasa_theme.dart';

class _FakeUrlOpener implements UrlOpener {
  _FakeUrlOpener({this.result = true});
  final bool result;
  String? lastUrl;

  @override
  Future<bool> open(String url) async {
    lastUrl = url;
    return result;
  }
}

Widget _wrap(Widget child) => MaterialApp(theme: NivasaTheme.light(), home: child);

// The success path calls Navigator.of(context).pop() — give it a real stack to pop from,
// same reasoning as change_password_screen_test.dart's _wrap.
Widget _wrapWithStack(UrlOpener opener) {
  return MaterialApp(
    theme: NivasaTheme.light(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppFeedbackScreen(urlOpener: opener))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('typing nothing and sending shows a validation error', (tester) async {
    final opener = _FakeUrlOpener();
    await tester.pumpWidget(_wrap(AppFeedbackScreen(urlOpener: opener)));

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Write a message before sending'), findsOneWidget);
    expect(opener.lastUrl, isNull);
  });

  testWidgets('sending opens a mailto: link to the support address with the message as the body', (tester) async {
    final opener = _FakeUrlOpener();
    await tester.pumpWidget(_wrapWithStack(opener));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'The rent reminder never showed up');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(opener.lastUrl, isNotNull);
    final uri = Uri.parse(opener.lastUrl!);
    expect(uri.scheme, 'mailto');
    expect(uri.path, supportEmail);
    expect(uri.queryParameters['body'], 'The rent reminder never showed up');
  });

  testWidgets('shows a fallback message when no email app is available', (tester) async {
    final opener = _FakeUrlOpener(result: false);
    await tester.pumpWidget(_wrap(AppFeedbackScreen(urlOpener: opener)));

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No email app found'), findsOneWidget);
  });
}
