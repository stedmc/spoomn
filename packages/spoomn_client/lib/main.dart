import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/providers/settings_provider.dart';
import 'src/router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  await _initAnonymousSession();

  final prefs = await SharedPreferences.getInstance();

  _listenDeepLinks();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const SpoomnApp(),
    ),
  );
}

void _listenDeepLinks() {
  AppLinks().uriLinkStream.listen((uri) {
    // spoomn://join/CODE → host='join', path='/CODE' → router path '/join/CODE'
    // https://spoomn.app/join/CODE → path='/join/CODE' → router path '/join/CODE'
    String path;
    if (uri.scheme == 'spoomn' && uri.host == 'join') {
      path = '/join${uri.path}';
    } else {
      path = uri.path;
    }
    if (path.isNotEmpty) router.go(path);
  });
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
