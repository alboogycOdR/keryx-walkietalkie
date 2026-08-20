import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app.dart';
import 'package:keryx/features/face/face_view.dart';

void main() {
  testWidgets('KeryxApp boots to the face with no external ProviderScope', (
    tester,
  ) async {
    await tester.pumpWidget(const KeryxApp());
    // FaceScreen's initState kicks off async identity/settings/floor-engine
    // boot (TASK-004/012 territory) before the first real frame; let it
    // settle so we're asserting on the booted face, not the loading gap.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FaceView), findsOneWidget);
  });
}
