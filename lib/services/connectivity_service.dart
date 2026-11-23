// ignore_for_file: prefer_initializing_formals

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConnectivityService {
  ConnectivityService({
    SupabaseClient? supabase,
    Connectivity? connectivity,
  })  : _supabase = supabase,
        _connectivity = connectivity ?? Connectivity();

  final SupabaseClient? _supabase;
  final Connectivity _connectivity;

  Future<bool> hasNetwork() async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }

  Stream<bool> get networkChanges => _connectivity.onConnectivityChanged.map(
        (results) => results.any((result) => result != ConnectivityResult.none),
      );

  Future<bool> isSupabaseAvailable() async {
    final client = _supabase;
    if (client == null) return false;
    try {
      await client
          .from('queue_clients')
          .select('id')
          .limit(1)
          .timeout(const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }
}
