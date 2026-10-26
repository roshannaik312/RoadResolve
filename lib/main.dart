import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/cloud_sync.dart';
import 'services/driving_monitor.dart';
import 'services/report_portal.dart';
import 'services/report_store.dart';
import 'services/settings_store.dart';
import 'services/siri_bridge.dart';
import 'services/voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  PortalLinks.instance.attach();

  final auth = AuthService()..start();
  final driving = DrivingMonitor();
  final settings = SettingsStore(driving);
  final reports = ReportStore();
  await Future.wait([settings.load(), reports.load()]);
  // After the local load, so downloaded reports merge into what's on disk.
  CloudSync(
    auth: auth,
    store: reports,
    shareOnMap: () => settings.shareOnMap,
    sharingChanges: settings,
  ).start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: driving),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: reports),
        ChangeNotifierProvider(create: (_) => VoiceService()),
        Provider(create: (_) => SiriBridge(), dispose: (_, s) => s.dispose()),
      ],
      child: const ClearRoadsApp(),
    ),
  );
}
