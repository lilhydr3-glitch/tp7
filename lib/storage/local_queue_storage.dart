import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sync_status.dart';

class LocalQueueStorage {
  static Database? _database;
  static const _webStorageKey = 'waiting_queue_clients_v2';

  Future<Database> get database async {
    if (kIsWeb) throw UnsupportedError('SQLite is unavailable on web.');
    if (_database != null) return _database!;

    final databasePath = path.join(
      await getDatabasesPath(),
      'waiting_queue.db',
    );
    _database = await openDatabase(
      databasePath,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _database!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clients (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        user_id TEXT,
        lat REAL,
        lng REAL,
        location_accuracy_m REAL,
        location_captured_at TEXT,
        created_at TEXT NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final columns = await db.rawQuery('PRAGMA table_info(clients)');
      final hasUserId = columns.any((column) => column['name'] == 'user_id');
      if (!hasUserId) {
        await db.execute('ALTER TABLE clients ADD COLUMN user_id TEXT');
      }
    }
  }

  Future<void> saveClient(Map<String, dynamic> client) async {
    if (kIsWeb) {
      final clients = await _readWebClients();
      clients.removeWhere((record) => record['id'] == client['id']);
      clients.add(Map<String, dynamic>.from(client));
      await _writeWebClients(clients);
      return;
    }
    final db = await database;
    await db.insert(
      'clients',
      client,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getClients({String? userId}) async {
    if (kIsWeb) {
      final clients = await _readWebClients();
      if (userId == null) return clients;
      return clients.where((client) => client['user_id'] == userId).toList();
    }
    final db = await database;
    return db.query(
      'clients',
      where: userId == null ? null : 'user_id = ?',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getPendingClients({String? userId}) async {
    if (kIsWeb) {
      final clients = await getClients(userId: userId);
      return clients.where((client) {
        final status = client['sync_status'];
        return status == SyncStatus.pending.name ||
            status == SyncStatus.failed.name ||
            status == SyncStatus.syncing.name;
      }).toList()
        ..sort(_compareRecords);
    }

    final conditions = <String>['sync_status IN (?, ?, ?)'];
    final arguments = <Object?>[
      SyncStatus.pending.name,
      SyncStatus.failed.name,
      SyncStatus.syncing.name,
    ];
    if (userId != null) {
      conditions.add('user_id = ?');
      arguments.add(userId);
    }

    final db = await database;
    return db.query(
      'clients',
      where: conditions.join(' AND '),
      whereArgs: arguments,
      orderBy: 'created_at ASC, id ASC',
    );
  }

  Future<void> updateSyncStatus(String id, SyncStatus status) async {
    if (kIsWeb) {
      final clients = await _readWebClients();
      for (final client in clients) {
        if (client['id'] == id) client['sync_status'] = status.name;
      }
      await _writeWebClients(clients);
      return;
    }
    final db = await database;
    await db.update(
      'clients',
      {'sync_status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteClient(String id) async {
    if (kIsWeb) {
      final clients = await _readWebClients();
      clients.removeWhere((client) => client['id'] == id);
      await _writeWebClients(clients);
      return;
    }
    final db = await database;
    await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> _readWebClients() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_webStorageKey);
    if (encoded == null) return [];
    return (jsonDecode(encoded) as List<dynamic>)
        .map((record) => Map<String, dynamic>.from(record as Map))
        .toList();
  }

  Future<void> _writeWebClients(List<Map<String, dynamic>> clients) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_webStorageKey, jsonEncode(clients));
  }

  int _compareRecords(Map<String, dynamic> first, Map<String, dynamic> second) {
    final createdAt =
        (first['created_at'] as String).compareTo(second['created_at'] as String);
    return createdAt != 0
        ? createdAt
        : (first['id'] as String).compareTo(second['id'] as String);
  }
}
