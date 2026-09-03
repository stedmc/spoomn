import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'package:spoomn_server/src/db/supabase_client.dart';
import 'package:spoomn_server/src/router.dart';

void main() async {
  await initSupabase();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cors())
      .addHandler(buildRouter().call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);

  stderr.writeln('Server listening on port ${server.port}');
}

Middleware _cors() {
  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      try {
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      } catch (e, st) {
        stderr.writeln('Unhandled error: $e\n$st');
        return Response.internalServerError(
          body: '{"error":{"code":"INTERNAL","message":"Internal server error"}}',
          headers: {..._corsHeaders, 'Content-Type': 'application/json'},
        );
      }
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
};
