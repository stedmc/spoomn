import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/game_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.pendingJoinCode});

  final String? pendingJoinCode;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      await client.auth.signInAnonymously();
    }

    if (!mounted) return;

    final code = widget.pendingJoinCode;
    if (code != null) {
      try {
        final result = await ref.read(gameServiceProvider).joinRoom(code);
        if (!mounted) return;
        final roomId = (result['room'] as Map<String, dynamic>)['id'] as String;
        context.go('/lobby/$roomId');
      } on GameServiceException catch (e) {
        if (!mounted) return;
        context.go('/dashboard');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join game: ${e.message}')),
        );
      } catch (_) {
        if (!mounted) return;
        context.go('/dashboard');
      }
    } else {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
