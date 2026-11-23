import '../models/client.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../storage/local_queue_storage.dart';

class SyncService {
  SyncService(this._storage, this._repository);

  final LocalQueueStorage _storage;
  final QueueRepository _repository;
  bool _isSyncing = false;

  /// Pushes this user's pending registrations to Supabase.
  ///
  /// Returns the number of entries that were synchronized successfully.
  Future<int> synchronize({required String userId}) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    var synchronizedCount = 0;
    try {
      final pendingRecords = await _storage.getPendingClients(userId: userId);
      for (final record in pendingRecords) {
        final id = record['id'] as String;
        try {
          await _storage.updateSyncStatus(id, SyncStatus.syncing);
          final client = Client.fromLocalMap(record);
          await _repository.registerOnServer(client);
          await _storage.deleteClient(id);
          synchronizedCount++;
        } catch (_) {
          await _storage.updateSyncStatus(id, SyncStatus.failed);
        }
      }
    } finally {
      _isSyncing = false;
    }
    return synchronizedCount;
  }
}
