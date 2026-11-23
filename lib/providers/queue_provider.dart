// Named constructor parameters intentionally assign private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/client.dart';
import '../models/queue_state.dart';
import '../models/sync_status.dart';
import '../repositories/queue_repository.dart';
import '../services/geolocation_service.dart';
import '../services/sync_service.dart';
import '../storage/local_queue_storage.dart';

class QueueProvider extends ChangeNotifier {
  QueueProvider({
    required QueueRepository repository,
    required GeolocationService geolocationService,
    required LocalQueueStorage storage,
    required SyncService syncService,
    required SupabaseClient supabase,
  })  : _repository = repository,
        _geolocationService = geolocationService,
        _storage = storage,
        _syncService = syncService,
        _supabase = supabase;

  final QueueRepository _repository;
  final GeolocationService _geolocationService;
  final LocalQueueStorage _storage;
  final SyncService _syncService;
  final SupabaseClient _supabase;
  final Uuid _uuid = const Uuid();

  final List<Client> _clients = [];
  QueueState _state = QueueState.initial;
  String? _errorMessage;
  int _page = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  bool _isJoining = false;
  bool _isLeaving = false;
  int? _myPosition;

  List<Client> get clients => List.unmodifiable(_clients);
  QueueState get state => _state;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;
  bool get isJoining => _isJoining;
  bool get isLeaving => _isLeaving;
  String? get errorMessage => _errorMessage;
  int get queueLength => _clients.length;
  int? get myPosition => myClient?.position ?? _myPosition;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  Client? get myClient {
    final userId = _currentUserId;
    for (final client in _clients) {
      if (client.isMine || (userId != null && client.userId == userId)) {
        return client;
      }
    }
    return null;
  }

  static int _compareClients(Client first, Client second) {
    final byDate = first.createdAt.compareTo(second.createdAt);
    return byDate != 0 ? byDate : first.id.compareTo(second.id);
  }

  void reset() {
    _clients.clear();
    _state = QueueState.initial;
    _errorMessage = null;
    _page = 0;
    _hasMore = true;
    _myPosition = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_state == QueueState.loading) return;

    _state = QueueState.loading;
    _errorMessage = null;
    notifyListeners();

    final userId = _currentUserId;
    var serverClients = <Client>[];
    Object? serverError;

    try {
      serverClients = await _repository.fetchPage(offset: 0, limit: _pageSize);
    } catch (error) {
      serverError = error;
    }

    var pendingClients = <Client>[];
    if (userId != null) {
      try {
        final rows = await _storage.getPendingClients(userId: userId);
        pendingClients = rows.map(Client.fromLocalMap).toList();
      } catch (_) {
        // Local storage is unavailable (for example on web before setup).
      }
    }

    final merged = <String, Client>{};
    for (final client in serverClients) {
      merged[client.id] = client;
    }
    for (final client in pendingClients) {
      merged.putIfAbsent(client.id, () => client);
    }

    _clients
      ..clear()
      ..addAll(merged.values.toList()..sort(_compareClients));
    _page = 0;
    _hasMore = serverClients.length >= _pageSize;

    if (_clients.isEmpty && serverError != null) {
      _state = QueueState.error;
      _errorMessage = _friendlyError(serverError);
    } else {
      _state = _clients.isEmpty ? QueueState.empty : QueueState.loaded;
      _errorMessage =
          serverError == null ? null : _friendlyError(serverError);
    }

    _myPosition = await _fetchMyPosition();
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _state != QueueState.loaded) return;

    _isLoadingMore = true;
    notifyListeners();
    try {
      final nextPage = _page + 1;
      final newClients = await _repository.fetchPage(
        offset: nextPage * _pageSize,
        limit: _pageSize,
      );
      final existingIds = _clients.map((client) => client.id).toSet();
      final uniqueClients =
          newClients.where((client) => !existingIds.contains(client.id));
      _clients.addAll(uniqueClients);
      _clients.sort(_compareClients);
      _page = nextPage;
      if (newClients.length < _pageSize) {
        _hasMore = false;
      }
    } catch (_) {
      // Keep the current page; scrolling again retries the request.
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<bool> joinQueue(String name) async {
    final userId = _currentUserId;
    final trimmedName = name.trim();

    if (userId == null) {
      _errorMessage = 'You must be signed in to join the queue.';
      notifyListeners();
      return false;
    }
    if (trimmedName.isEmpty) {
      _errorMessage = 'Please enter your name.';
      notifyListeners();
      return false;
    }
    if (myClient != null) {
      _errorMessage = 'You are already in the waiting queue.';
      notifyListeners();
      return false;
    }

    _isJoining = true;
    _errorMessage = null;
    _myPosition = null;
    notifyListeners();

    try {
      final position = await _geolocationService.getCurrentPosition();
      final now = DateTime.now().toUtc();
      final client = Client(
        id: _uuid.v4(),
        name: trimmedName,
        userId: userId,
        lat: position?.latitude,
        lng: position?.longitude,
        locationAccuracy: position?.accuracy,
        locationCapturedAt: position == null ? null : now,
        createdAt: now,
        syncStatus: SyncStatus.pending,
      );

      await _storage.saveClient(client.toLocalMap());
      _clients.add(client);
      _clients.sort(_compareClients);
      if (_state == QueueState.empty) {
        _state = QueueState.loaded;
      }
      notifyListeners();

      await _syncService.synchronize(userId: userId);
      await refresh();
      return true;
    } catch (error) {
      _errorMessage = _friendlyError(error);
      return false;
    } finally {
      _isJoining = false;
      notifyListeners();
    }
  }

  Future<void> synchronizePending() async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      final synchronizedCount = await _syncService.synchronize(userId: userId);
      if (synchronizedCount > 0) {
        await refresh();
      }
    } catch (_) {
      // Pending entries stay queued locally and are retried later.
    }
  }

  Future<bool> leaveQueue() async {
    final mine = myClient;
    if (mine == null) return false;

    _isLeaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (mine.syncStatus == SyncStatus.synced) {
        await _repository.removeFromServer(mine.id);
      }
      await _storage.deleteClient(mine.id);
      _clients.removeWhere((client) => client.id == mine.id);
      _myPosition = null;
      if (_clients.isEmpty) {
        _state = QueueState.empty;
      }
      return true;
    } catch (error) {
      _errorMessage = _friendlyError(error);
      return false;
    } finally {
      _isLeaving = false;
      notifyListeners();
    }
  }

  Future<void> startRealtime() async {
    await _repository.startRealtime(
      onInsert: (client) {
        final existingIndex =
            _clients.indexWhere((item) => item.id == client.id);
        if (existingIndex >= 0) {
          if (client.isMine) {
            _clients[existingIndex] = client;
          }
        } else {
          _clients.add(client);
          _clients.sort(_compareClients);
        }
        if (_state == QueueState.empty) {
          _state = QueueState.loaded;
        }
        if (client.isMine && client.position != null) {
          _myPosition = client.position;
        }
        notifyListeners();
        unawaited(_refreshPositionSilently());
      },
      onDelete: (id) {
        final previousLength = _clients.length;
        _clients.removeWhere((client) => client.id == id);
        if (_clients.length != previousLength) {
          if (myClient == null) {
            _myPosition = null;
          }
          if (_clients.isEmpty) {
            _state = QueueState.empty;
          }
          notifyListeners();
          unawaited(_refreshPositionSilently());
        }
      },
    );
  }

  Future<void> stopRealtime() => _repository.stopRealtime();

  Future<void> _refreshPositionSilently() async {
    final position = await _fetchMyPosition();
    if (position != _myPosition) {
      _myPosition = position;
      notifyListeners();
    }
  }

  Future<int?> _fetchMyPosition() async {
    if (_currentUserId == null) return null;
    try {
      return await _repository.fetchMyPosition();
    } catch (_) {
      return null;
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('SocketException') ||
        message.contains('ClientException') ||
        message.contains('Failed host lookup') ||
        message.contains('timed out')) {
      return 'Network unavailable. Your registration is saved on this device '
          'and will sync automatically.';
    }
    if (message.contains('Authentication required')) {
      return 'Your session expired. Please sign in again.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    unawaited(stopRealtime());
    super.dispose();
  }
}
