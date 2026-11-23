import 'package:flutter_test/flutter_test.dart';

import 'package:workshop6/models/client.dart';
import 'package:workshop6/models/sync_status.dart';

void main() {
  group('Client model', () {
    test('without location reports hasLocation as false', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        createdAt: DateTime.now(),
      );

      expect(client.hasLocation, isFalse);
      expect(client.locationText, equals('Location not captured'));
    });

    test('toLocalMap preserves accuracy, syncStatus and ownership', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        userId: 'user-1',
        lat: 36.8065,
        lng: 10.1815,
        locationAccuracy: 5.5,
        createdAt: DateTime(2026, 1, 1),
        syncStatus: SyncStatus.pending,
      );

      final map = client.toLocalMap();

      expect(map['location_accuracy_m'], equals(5.5));
      expect(map['sync_status'], equals('pending'));
      expect(map['user_id'], equals('user-1'));
    });

    test('toSupabaseMap excludes local sync metadata', () {
      final client = Client(
        id: '1',
        name: 'Test Client',
        createdAt: DateTime.now(),
        syncStatus: SyncStatus.pending,
      );

      final map = client.toSupabaseMap();

      expect(map.containsKey('sync_status'), isFalse);
      expect(map.containsKey('user_id'), isFalse);
    });

    test('fromSupabaseMap reads ownership and queue position', () {
      final client = Client.fromSupabaseMap({
        'id': '2',
        'name': 'Ada',
        'user_id': 'user-2',
        'created_at': '2026-11-17T10:00:00Z',
        'is_mine': true,
        'position': 3,
      });

      expect(client.userId, equals('user-2'));
      expect(client.isMine, isTrue);
      expect(client.position, equals(3));
      expect(client.syncStatus, equals(SyncStatus.synced));
    });
  });
}
