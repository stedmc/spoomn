import 'dart:io';

import 'package:supabase/supabase.dart';

late final SupabaseClient supabase;

Future<void> initSupabase() async {
  final url = Platform.environment['SUPABASE_URL'];
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (url == null || serviceKey == null) {
    throw StateError(
      'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set',
    );
  }

  supabase = SupabaseClient(url, serviceKey);
}
