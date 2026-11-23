import 'sync_status.dart';

class Client {
  const Client({
    required this.id,
    required this.name,
    this.userId,
    this.lat,
    this.lng,
    this.locationAccuracy,
    this.locationCapturedAt,
    required this.createdAt,
    this.syncStatus = SyncStatus.synced,
    this.isMine = false,
    this.position,
  });

  final String id;
  final String name;

  /// The Supabase Auth user that created this queue entry.
  final String? userId;
  final double? lat;
  final double? lng;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final DateTime createdAt;
  final SyncStatus syncStatus;

  /// True when the row belongs to the signed-in user (computed by the server).
  final bool isMine;

  /// One-based position in the shared queue (computed by the server).
  final int? position;

  bool get hasLocation => lat != null && lng != null;

  String get locationText => hasLocation
      ? '${lat!.toStringAsFixed(4)}, ${lng!.toStringAsFixed(4)}'
      : 'Location not captured';

  Client copyWith({
    SyncStatus? syncStatus,
    bool? isMine,
    int? position,
  }) =>
      Client(
        id: id,
        name: name,
        userId: userId,
        lat: lat,
        lng: lng,
        locationAccuracy: locationAccuracy,
        locationCapturedAt: locationCapturedAt,
        createdAt: createdAt,
        syncStatus: syncStatus ?? this.syncStatus,
        isMine: isMine ?? this.isMine,
        position: position ?? this.position,
      );

  /// Serialization for Supabase (business data only).
  Map<String, dynamic> toSupabaseMap() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'location_accuracy_m': locationAccuracy,
        'location_captured_at': locationCapturedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  /// Serialization for SQLite (business data plus local sync metadata).
  Map<String, dynamic> toLocalMap() => {
        ...toSupabaseMap(),
        'user_id': userId,
        'sync_status': syncStatus.name,
      };

  factory Client.fromSupabaseMap(Map<String, dynamic> map) => Client(
        id: map['id'].toString(),
        name: map['name'] as String,
        userId: map['user_id'] as String?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
        locationCapturedAt: map['location_captured_at'] == null
            ? null
            : DateTime.parse(map['location_captured_at'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
        syncStatus: SyncStatus.synced,
        isMine: map['is_mine'] as bool? ?? false,
        position: (map['position'] as num?)?.toInt(),
      );

  factory Client.fromLocalMap(Map<String, dynamic> map) => Client(
        id: map['id'] as String,
        name: map['name'] as String,
        userId: map['user_id'] as String?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        locationAccuracy: (map['location_accuracy_m'] as num?)?.toDouble(),
        locationCapturedAt: map['location_captured_at'] == null
            ? null
            : DateTime.parse(map['location_captured_at'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
        syncStatus: SyncStatus.values.firstWhere(
          (status) => status.name == map['sync_status'],
          orElse: () => SyncStatus.pending,
        ),
      );
}
