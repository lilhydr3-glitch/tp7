import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';

class QueueRepository {
  QueueRepository(this._supabase);

  final SupabaseClient? _supabase;
  RealtimeChannel? _channel;

  SupabaseClient get _client {
    final client = _supabase;
    if (client == null) {
      throw StateError('Supabase is not configured.');
    }
    return client;
  }

  Future<List<Client>> fetchPage({
    required int offset,
    required int limit,
  }) async {
    if (_supabase == null) return [];
    final rows = await _client
        .from('queue_clients')
        .select()
        .order('created_at', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + limit - 1);
    return rows.map(Client.fromSupabaseMap).toList();
  }

  Future<Client> fetchClient(String id) async {
    final row = await _client
        .from('queue_clients')
        .select()
        .eq('id', id)
        .single();
    return Client.fromSupabaseMap(row);
  }

  Future<int?> fetchMyPosition() async {
    if (_supabase == null) return null;
    final row = await _client
        .from('queue_clients')
        .select('position')
        .eq('is_mine', true)
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    return (row?['position'] as num?)?.toInt();
  }

  Future<void> registerOnServer(Client client) async {
    await _client.rpc('register_queue_client', params: {
      'p_id': client.id,
      'p_name': client.name,
      'p_lat': client.lat,
      'p_lng': client.lng,
      'p_accuracy': client.locationAccuracy,
      'p_location_captured_at': client.locationCapturedAt?.toIso8601String(),
      'p_created_at': client.createdAt.toIso8601String(),
    });
  }

  Future<void> removeFromServer(String id) async {
    await _client.from('clients').delete().eq('id', id);
  }

  Future<void> startRealtime({
    required void Function(Client client) onInsert,
    required void Function(String id) onDelete,
  }) async {
    if (_supabase == null || _channel != null) return;
    _channel = _client
        .channel('waiting-room')
        ..onBroadcast(
          event: 'queue_client_inserted',
          callback: (payload) async {
            final id = payload['id']?.toString();
            if (id == null) return;
            try {
              onInsert(await fetchClient(id));
            } catch (_) {
              // The next refresh will recover a transient read failure.
            }
          },
        )
        ..onBroadcast(
          event: 'queue_client_deleted',
          callback: (payload) {
            final id = payload['id']?.toString();
            if (id != null) onDelete(id);
          },
        )
        ..subscribe();
  }

  Future<void> stopRealtime() async {
    final channel = _channel;
    _channel = null;
    if (channel != null && _supabase != null) {
      await _supabase.removeChannel(channel);
    }
  }
}
