import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() => runApp(const ProviderScope(child: KeryxApp()));

/// Temporary boot shell. TASK-017 replaces this with the assembled radio face.
class KeryxApp extends StatelessWidget {
  const KeryxApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Keryx',
        debugShowCheckedModeBanner: false,
        home: const Scaffold(body: Center(child: Text('KERYX'))),
      );
}
