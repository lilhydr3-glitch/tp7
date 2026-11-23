import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_connectivity.dart';
import '../models/queue_state.dart';
import '../models/sync_status.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/queue_provider.dart';
import '../widgets/client_card.dart';
import '../widgets/loading_widget.dart';
import '../widgets/offline_banner.dart';
import '../widgets/queue_empty_widget.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();

  bool _nameInitialized = false;
  AppConnectivity? _previousStatus;
  QueueProvider? _queue;
  ConnectivityProvider? _connectivity;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final queue = context.read<QueueProvider>();
      _queue = queue;
      queue.refresh();
      queue.startRealtime();
      queue.synchronizePending();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (!_nameInitialized) {
      _nameController.text = auth.displayName;
      _nameInitialized = true;
    }
    final connectivity = context.read<ConnectivityProvider>();
    connectivity.removeListener(_handleConnectivityChanged);
    connectivity.addListener(_handleConnectivityChanged);
    _connectivity = connectivity;
    _previousStatus = connectivity.status;
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _nameController.dispose();
    _connectivity?.removeListener(_handleConnectivityChanged);
    final queue = _queue;
    if (queue != null) {
      unawaited(queue.stopRealtime());
    }
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      context.read<QueueProvider>().loadMore();
    }
  }

  void _handleConnectivityChanged() {
    if (!mounted) return;
    final connectivity = _connectivity;
    if (connectivity == null) return;
    final wasOnline = _previousStatus == AppConnectivity.online;
    _previousStatus = connectivity.status;
    if (connectivity.isOnline && !wasOnline) {
      final queue = _queue ?? context.read<QueueProvider>();
      queue.synchronizePending();
      queue.refresh();
    }
  }

  Future<void> _join(QueueProvider queue) async {
    final joined = await queue.joinQueue(_nameController.text);
    if (!mounted) return;
    if (joined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You joined the queue.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(queue.errorMessage ?? 'Unable to join the queue.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _confirmLeave(QueueProvider queue) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the queue?'),
        content: const Text(
          'Your place will be given up and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (shouldLeave != true) return;

    final left = await queue.leaveQueue();
    if (!mounted) return;
    if (!left) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(queue.errorMessage ?? 'Unable to leave the queue.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final connectivity = context.watch<ConnectivityProvider>();
    final queue = context.watch<QueueProvider>();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.meeting_room_rounded,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Waiting Room'),
          ],
        ),
        actions: [
          _ConnectionChip(status: connectivity.status),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (value) {
              if (value == 'signOut') {
                queue.reset();
                unawaited(auth.signOut());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (auth.email.isNotEmpty)
                      Text(
                        auth.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'signOut',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded),
                    SizedBox(width: 8),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CircleAvatar(
                radius: 18,
                child: Text(_initials(auth.displayName)),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            OfflineBanner(status: connectivity.status),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildJoinPanel(context, queue),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              '${queue.queueLength} '
                              '${queue.queueLength == 1 ? 'person' : 'people'} '
                              'waiting',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (queue.state == QueueState.loading &&
                                queue.clients.isNotEmpty)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildList(context, queue)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinPanel(BuildContext context, QueueProvider queue) {
    final theme = Theme.of(context);
    final mine = queue.myClient;

    if (mine != null) {
      final position = queue.myPosition;
      final isPending = mine.syncStatus != SyncStatus.synced;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                child: Text(
                  position == null ? '…' : '$position',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position == null
                          ? 'You are in the queue'
                          : 'You are number $position',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPending
                          ? 'Saved on this device. It will sync when you are online.'
                          : 'Keep this page open to watch your position update.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed:
                    queue.isLeaving ? null : () => _confirmLeave(queue),
                child: queue.isLeaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Leave'),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _join(queue),
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: queue.isJoining ? null : () => _join(queue),
              icon: queue.isJoining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded),
              label: const Text('Join queue'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, QueueProvider queue) {
    if (queue.clients.isEmpty) {
      if (queue.state == QueueState.loading ||
          queue.state == QueueState.initial) {
        return const LoadingWidget(message: 'Connecting to the waiting room...');
      }
      if (queue.state == QueueState.error) {
        return _ErrorState(
          message: queue.errorMessage ?? 'Failed to load the queue.',
          onRetry: queue.refresh,
        );
      }
      return const QueueEmptyWidget();
    }

    final itemCount = queue.clients.length + (queue.hasMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: queue.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= queue.clients.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final client = queue.clients[index];
          final userId = context.read<AuthProvider>().user?.id;
          final isMine = client.isMine ||
              (userId != null && client.userId == userId);
          return ClientCard(
            client: client,
            position: client.position ?? index + 1,
            isMine: isMine,
          );
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.status});

  final AppConnectivity status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      AppConnectivity.online => ('Realtime', Colors.green.shade600),
      AppConnectivity.checking => ('Checking', Colors.blue.shade600),
      AppConnectivity.offline => ('Offline', Colors.red.shade600),
      AppConnectivity.backendUnavailable => (
          'Server unreachable',
          Colors.orange.shade700,
        ),
    };

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 36,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Connection error',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
