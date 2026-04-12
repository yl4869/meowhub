import 'package:flutter_test/flutter_test.dart';

import 'package:meowhub/main.dart';

void main() {
  testWidgets('renders the home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MeowHubApp());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('MeowHub'), findsOneWidget);
    expect(find.text('当前线路'), findsOneWidget);
  });
}
