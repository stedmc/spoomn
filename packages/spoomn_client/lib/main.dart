import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  await _initAnonymousSession();

  runApp(const ProviderScope(child: SpoomnApp()));
}

Future<void> _initAnonymousSession() async {
  final client = Supabase.instance.client;
  if (client.auth.currentSession == null) {
    await client.auth.signInAnonymously();
  }
}

class SpoomnApp extends StatelessWidget {
  const SpoomnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Spoomn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      routerConfig: router,
    );
  }
}
