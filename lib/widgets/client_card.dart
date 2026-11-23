import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/sync_status.dart';

class ClientCard extends StatelessWidget {
  const ClientCard({
    super.key,
    required this.client,
    required this.position,
    required this.isMine,
  });

  final Client client;
  final int position;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = client.syncStatus != SyncStatus.synced;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isMine
          ? theme.colorScheme.primaryContainer.withAlpha(140)
          : theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isMine
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: isMine
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
          child: Text(
            '$position',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                client.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isMine) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'You',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            isPending
                ? 'Pending sync — saved on this device'
                : _waitingSince(client.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (client.hasLocation)
              Tooltip(
                message: 'Location shared',
                child: Icon(
                  Icons.location_on_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            if (isPending) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.cloud_upload_outlined,
                size: 20,
                color: theme.colorScheme.tertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _waitingSince(DateTime createdAt) {
    final elapsed = DateTime.now().toUtc().difference(createdAt.toUtc());
    if (elapsed.inMinutes < 1) return 'Waiting just now';
    if (elapsed.inMinutes < 60) return 'Waiting ${elapsed.inMinutes} min';
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    return 'Waiting ${hours}h ${minutes}min';
  }
}
