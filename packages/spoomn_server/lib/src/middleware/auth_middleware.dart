import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:supabase/supabase.dart';

import '../db/supabase_client.dart';

typedef AuthedHandler = Future<Response> Function(
  Request request,
  String playerId,
);

Handler authMiddleware(AuthedHandler handler) {
  return (Request request) async {
    final authHeader = request.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return errorJson(401, 'UNAUTHORIZED', 'Missing or invalid Authorization header');
    }

    final jwt = authHeader.substring(7);

    try {
      final response = await supabase.auth.getUser(jwt);
      final user = response.user;
      if (user == null) {
        return errorJson(401, 'UNAUTHORIZED', 'Invalid token');
      }
      return await handler(request, user.id);
    } on AuthException {
      return errorJson(401, 'UNAUTHORIZED', 'Token verification failed');
    }
  };
}

Response okJson(Map<String, dynamic> body) => Response.ok(
      jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Response errorJson(int status, String code, String message) => Response(
      status,
      body: jsonEncode({'error': {'code': code, 'message': message}}),
      headers: {'content-type': 'application/json'},
    );
