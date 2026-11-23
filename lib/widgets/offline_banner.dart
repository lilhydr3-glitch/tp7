import 'package:flutter/material.dart';

import '../models/app_connectivity.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.status});

  final AppConnectivity status;

  @override
  Widget build(BuildContext context) {
    if (status == AppConnectivity.online) {
      return const SizedBox.shrink();
    }

    final (message, color) = switch (status) {
      AppConnectivity.offline => ('No network connection', Colors.red.shade700),
      AppConnectivity.backendUnavailable => (
          'Waiting-room server unavailable',
          Colors.orange.shade800,
        ),
      AppConnectivity.checking => ('Checking connection...', Colors.blue),
      AppConnectivity.online => ('Connected', Colors.green),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
