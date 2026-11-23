import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._supabase);

  final SupabaseClient _supabase;
  StreamSubscription<AuthState>? _authSubscription;

  Session? _session;
  Profile? _profile;
  bool _initializing = true;
  bool _busy = false;
  String? _errorMessage;
  String? _noticeMessage;

  Session? get session => _session;
  User? get user => _session?.user;
  Profile? get profile => _profile;
  bool get isAuthenticated => _session != null;
  bool get isInitializing => _initializing;
  bool get isBusy => _busy;
  String? get errorMessage => _errorMessage;
  String? get noticeMessage => _noticeMessage;
  String get email => user?.email ?? '';

  String get displayName {
    final profileName = _profile?.displayName;
    if (profileName != null && profileName.trim().isNotEmpty) {
      return profileName.trim();
    }
    final metadataName = user?.userMetadata?['display_name'];
    if (metadataName is String && metadataName.trim().isNotEmpty) {
      return metadataName.trim();
    }
    final address = user?.email;
    if (address != null && address.contains('@')) {
      return address.split('@').first;
    }
    return 'Guest';
  }

  Future<void> initialize() async {
    _session = _supabase.auth.currentSession;
    _authSubscription = _supabase.auth.onAuthStateChange.listen((state) {
      final previousUserId = _session?.user.id;
      _session = state.session;
      if (_session == null) {
        _profile = null;
      } else if (previousUserId != _session!.user.id) {
        unawaited(_loadProfile(_session!.user.id));
      }
      notifyListeners();
    });

    final currentUserId = _session?.user.id;
    if (currentUserId != null) {
      await _loadProfile(currentUserId);
    }
    _initializing = false;
    notifyListeners();
  }

  Future<void> _loadProfile(String userId) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select('id, display_name, created_at')
          .eq('id', userId)
          .maybeSingle();
      _profile = row == null ? null : Profile.fromMap(row);
      _errorMessage = null;
      notifyListeners();
    } catch (_) {
      // Profile data is optional; metadata is used as a fallback.
    }
  }

  Future<bool> signIn({
    required String email,
    required String password,
  }) {
    return _runAuth(() async {
      final response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _session = response.session;
      final signedInUser = response.user;
      if (signedInUser != null) {
        await _loadProfile(signedInUser.id);
      }
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _runAuth(() async {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
      if (response.session == null) {
        _session = null;
        _profile = null;
        _noticeMessage =
            'Account created. Check your email to confirm it, then sign in.';
      } else {
        _session = response.session;
        final signedUpUser = response.user;
        if (signedUpUser != null) {
          await _loadProfile(signedUpUser.id);
        }
      }
    });
  }

  Future<void> signOut() async {
    _busy = true;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();
    try {
      await _supabase.auth.signOut();
      _session = null;
      _profile = null;
    } on AuthException catch (error) {
      _errorMessage = error.message;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _runAuth(Future<void> Function() action) async {
    _busy = true;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (error) {
      _errorMessage = _messageFor(error.message);
      return false;
    } catch (error) {
      _errorMessage = _messageFor(error.toString());
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _messageFor(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Invalid email or password.';
    }
    if (message.contains('already registered')) {
      return 'This email is already registered. Try signing in instead.';
    }
    if (message.contains('Password should be')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (message.contains('Email not confirmed')) {
      return 'Please confirm your email address before signing in.';
    }
    if (message.contains('socket') || message.contains('ClientException')) {
      return 'Network unavailable. Check your connection and try again.';
    }
    return message;
  }

  void clearMessages() {
    if (_errorMessage == null && _noticeMessage == null) return;
    _errorMessage = null;
    _noticeMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
