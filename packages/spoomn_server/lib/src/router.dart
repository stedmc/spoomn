import 'package:shelf_router/shelf_router.dart';

import 'handlers/action_handler.dart';
import 'handlers/room_handler.dart';
import 'middleware/auth_middleware.dart';

Router buildRouter() {
  final router = Router();

  // Health check (no auth)
  router.get('/health', (request) async {
    return okJson({'status': 'ok'});
  });

  // Auth-gated routes
  final authed = Router()
    // Profile
    ..post('/api/profile/push-token', authMiddleware(updatePushToken))
    // Rooms
    ..get('/api/my-games', authMiddleware(listMyGames))
    ..post('/api/rooms', authMiddleware(createRoom))
    ..post('/api/rooms/<roomCode>/join', authMiddleware(joinRoom))
    ..post('/api/rooms/<roomId>/rejoin', authMiddleware(rejoinRoom))
    ..post('/api/rooms/<roomId>/start', authMiddleware(startRoom))
    ..post('/api/rooms/<roomId>/begin', authMiddleware(beginGame))
    ..post('/api/rooms/<roomId>/config', authMiddleware(updateRoomConfig))
    ..post('/api/rooms/<roomId>/debug-add-player', authMiddleware(debugAddPlayer))
    ..post('/api/rooms/<roomId>/remove-player', authMiddleware(removePlayer))
    ..post('/api/rooms/<roomId>/pause', authMiddleware(pauseRoom))
    ..post('/api/rooms/<roomId>/resume', authMiddleware(resumeRoom))
    ..post('/api/rooms/<roomId>/connect', authMiddleware(connectPlayer))
    ..post('/api/rooms/<roomId>/disconnect', authMiddleware(disconnectPlayer))
    // Actions
    ..post('/api/rooms/<roomId>/actions', authMiddleware(handleAction));

  router.mount('/', authed.call);

  return router;
}
