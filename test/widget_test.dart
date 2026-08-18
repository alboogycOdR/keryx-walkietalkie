import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/main.dart';

void main() {
  testWidgets('boots the Keryx application shell', (tester) async {
    await tester.pumpWidget(const KeryxApp());

    expect(find.text('KERYX'), findsOneWidget);
  });
}
