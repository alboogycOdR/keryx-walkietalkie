import 'package:flutter/widgets.dart';
import 'package:keryx/app.dart';

// Re-exported so `package:keryx/main.dart` keeps exposing `KeryxApp`, the
// same public surface the pre-existing root `test/widget_test.dart` (not in
// this task's `Owned_Paths`) imports it through.
export 'package:keryx/app.dart' show KeryxApp;

void main() => runApp(const KeryxApp());
