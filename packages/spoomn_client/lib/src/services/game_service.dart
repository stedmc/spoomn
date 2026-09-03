import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'game_service.g.dart';

@riverpod
GameService gameService(GameServiceRef ref) => GameService();

class GameService {
  static const String _baseUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://localhost:8080',
  );

  Future<Map<String, dynamic>> submitAction(
    String roomId,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw StateError('No active session');

    final response = await http.post(
      Uri.parse('$_baseUrl/api/rooms/$roomId/actions'),
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'action': action, 'payload': payload}),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final error = body['error'] as Map<String, dynamic>?;
      throw GameServiceException(
        code: error?['code'] as String? ?? 'UNKNOWN',
        message: error?['message'] as String? ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }

    return body;
  }

  Future<Map<String, dynamic>> createRoom({
    required int maxPlayers,
    required String playMode,
    Map<String, dynamic> config = const {},
  }) => _post('/api/rooms', {
        'max_players': maxPlayers,
        'play_mode': playMode,
        'config': config,
      });

  Future<Map<String, dynamic>> joinRoom(String roomCode) =>
      _post('/api/rooms/$roomCode/join', {});

  Future<Map<String, dynamic>> rejoinRoom(
    String roomId, {
    String? deviceToken,
  }) =>
      _post('/api/rooms/$roomId/rejoin', {
        if (deviceToken != null) 'device_token': deviceToken,
      });

  Future<Map<String, dynamic>> startRoom(String roomId) =>
      _post('/api/rooms/$roomId/start', {});

  Future<Map<String, dynamic>> beginGame(String roomId) =>
      _post('/api/rooms/$roomId/begin', {});

  Future<void> pauseRoom(String roomId) => _post('/api/rooms/$roomId/pause', {});

  Future<void> resumeRoom(String roomId) => _post('/api/rooms/$roomId/resume', {});

  Future<Map<String, dynamic>> debugAddPlayer(String roomId) =>
      _post('/api/rooms/$roomId/debug-add-player', {});

  Future<void> removePlayer(String roomId, String targetPlayerId) =>
      _post('/api/rooms/$roomId/remove-player', {'player_id': targetPlayerId});

  Future<void> updateConfig(String roomId, Map<String, dynamic> updates) async {
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw StateError('No active session');
    final response = await http.post(
      Uri.parse('$_baseUrl/api/rooms/$roomId/config'),
      headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
      body: jsonEncode(updates),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw GameServiceException(
        code: error?['code'] as String? ?? 'UNKNOWN',
        message: error?['message'] as String? ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }
  }

  Future<void> setDebugMode(String roomId, {required bool enabled}) =>
      updateConfig(roomId, {'debug_mode': enabled});

  Future<void> connect(String roomId) => _post('/api/rooms/$roomId/connect', {});

  Future<void> disconnect(String roomId) =>
      _post('/api/rooms/$roomId/disconnect', {});

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final jwt = Supabase.instance.client.auth.currentSession?.accessToken;
    if (jwt == null) throw StateError('No active session');

    final response = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw GameServiceException(
        code: error?['code'] as String? ?? 'UNKNOWN',
        message: error?['message'] as String? ?? 'Unknown error',
        statusCode: response.statusCode,
      );
    }

    return decoded;
  }
}

class GameServiceException implements Exception {
  const GameServiceException({
    required this.code,
    required this.message,
    required this.statusCode,
  });

  final String code;
  final String message;
  final int statusCode;

  @override
  String toString() => 'GameServiceException($statusCode $code): $message';
}
