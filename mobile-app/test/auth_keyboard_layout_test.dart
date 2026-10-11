import 'package:CureNurture/pages/auth/forgot_password_page.dart';
import 'package:CureNurture/pages/auth/login_page.dart';
import 'package:CureNurture/pages/auth/signup_page.dart';
import 'package:CureNurture/theme/auth_theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(360, 740);
const _keyboardHeight = 300.0;

final _background = find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName.contains('image 4'),
);

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

Future<void> _openKeyboard(WidgetTester tester, Finder field) async {
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardHeight);
  await tester.pumpAndSettle();
}

/// The background must keep the exact same on-screen rect while the
/// keyboard is open, and the [action] must still be reachable above it.
Future<void> _expectStableBackground(
  WidgetTester tester, {
  required Widget page,
  required Finder field,
  required Finder action,
}) async {
  await _pump(tester, page);
  final before = tester.getRect(_background);
  expect(before, Offset.zero & _screen);

  await _openKeyboard(tester, field);
  expect(tester.takeException(), isNull);
  expect(tester.getRect(_background), before);

  await tester.scrollUntilVisible(
    action,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(
    tester.getRect(action).bottom,
    lessThanOrEqualTo(_screen.height - _keyboardHeight),
  );

  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
  expect(tester.getRect(_background), before);
}

void main() {
  setUp(() => AuthThemeController.mode.value = ThemeMode.dark);

  testWidgets('Login: background stays put when the keyboard opens', (
    tester,
  ) async {
    await _expectStableBackground(
      tester,
      page: const LoginPage(),
      field: find.byType(TextField).last,
      action: find.text('Log In'),
    );
  });

  testWidgets('Create Account: background stays put, NEXT reachable', (
    tester,
  ) async {
    await _expectStableBackground(
      tester,
      page: const SignupPage(),
      field: find.byType(TextField).first,
      action: find.text('NEXT'),
    );
  });

  testWidgets('Forgot Password: background stays put', (tester) async {
    await _pump(tester, const ForgotPasswordPage());
    final before = tester.getRect(_background);

    await _openKeyboard(tester, find.byType(TextField).first);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(_background), before);
  });

  testWidgets('focused field is scrolled above the keyboard', (tester) async {
    await _pump(tester, const SignupPage());
    final lastField = find.byType(TextField).last;
    await tester.ensureVisible(lastField);
    await _openKeyboard(tester, lastField);

    expect(
      tester.getRect(lastField).bottom,
      lessThanOrEqualTo(_screen.height - _keyboardHeight),
    );
  });
}
