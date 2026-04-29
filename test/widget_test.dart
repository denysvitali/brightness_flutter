import 'package:flutter_test/flutter_test.dart';

import 'package:brightness_flutter/main.dart';

void main() {
  testWidgets('shows the build check app', (WidgetTester tester) async {
    await tester.pumpWidget(const BrightnessApp());

    expect(find.text('Brightness'), findsWidgets);
    expect(find.text('Build check app'), findsOneWidget);
  });
}
