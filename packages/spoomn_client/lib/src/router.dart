import 'package:go_router/go_router.dart';

import 'screens/dashboard_screen.dart';
import 'screens/game_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/game_over_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/splash_screen.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/lobby/:roomId',
      builder: (context, state) => LobbyScreen(
        roomId: state.pathParameters['roomId']!,
        showDebugMode: state.uri.queryParameters['gamemode'] == 'debug',
      ),
    ),
    GoRoute(
      path: '/game/:roomId',
      builder: (context, state) => GameScreen(
        roomId: state.pathParameters['roomId']!,
      ),
    ),
    GoRoute(
      path: '/game-over/:roomId',
      builder: (context, state) => GameOverScreen(
        roomId: state.pathParameters['roomId']!,
      ),
    ),
    // Deep link: spoomn://join/K7X2MQ or /join/K7X2MQ
    GoRoute(
      path: '/join/:roomCode',
      builder: (context, state) => SplashScreen(
        pendingJoinCode: state.pathParameters['roomCode'],
      ),
    ),
  ],
);
