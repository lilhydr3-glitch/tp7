import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workshop6/models/app_connectivity.dart';
import 'package:workshop6/widgets/offline_banner.dart';

void main() {
  testWidgets('offline banner is displayed when offline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineBanner(status: AppConnectivity.offline),
        ),
      ),
    );

    expect(find.text('No network connection'), findsOneWidget);
  });

  testWidgets('offline banner is hidden when online', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineBanner(status: AppConnectivity.online),
        ),
      ),
    );

    expect(find.text('No network connection'), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });
}
