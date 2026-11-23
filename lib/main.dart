import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/queue_provider.dart';
import 'repositories/queue_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/queue_screen.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';
import 'services/sync_service.dart';
import 'storage/local_queue_storage.dart';

const String _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://fosgclukncaiwerxkgmp.supabase.co',
);

// Public client key (safe to ship in a Flutter app). Override it with
// `--dart-define=SUPABASE_PUBLISHABLE_KEY=...` for another project.
const String _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_D54xZzaiN6kiQUBhI_EdYg_ouu5-4w8',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );

  runApp(const WaitingQueueApp());
}

class WaitingQueueApp extends StatelessWidget {
  const WaitingQueueApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final storage = LocalQueueStorage();
    final repository = QueueRepository(supabase);
    final syncService = SyncService(storage, repository);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(supabase)..initialize(),
        ),
        ChangeNotifierProvider<ConnectivityProvider>(
          create: (_) => ConnectivityProvider(
            ConnectivityService(supabase: supabase),
          )..initialize(),
        ),
        ChangeNotifierProvider<QueueProvider>(
          create: (_) => QueueProvider(
            repository: repository,
            geolocationService: GeolocationService(),
            storage: storage,
            syncService: syncService,
            supabase: supabase,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Waiting Room',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2563EB),
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isInitializing) {
      return const _SplashScreen();
    }
    if (!auth.isAuthenticated) {
      return const AuthScreen();
    }
    return QueueScreen(key: ValueKey(auth.user?.id));
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.meeting_room_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
