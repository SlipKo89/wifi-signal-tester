import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'settings/settings_controller.dart';
import 'state/monitor_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bundled font — declare its licence for the in-app licences page.
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Noto Sans'],
      'Noto Sans is licensed under the SIL Open Font License, Version 1.1.\n'
      'https://openfontlicense.org',
    );
  });

  final settings = SettingsController();
  await settings.load();
  runApp(WifiApkApp(settings: settings));
}

class WifiApkApp extends StatelessWidget {
  final SettingsController settings;
  const WifiApkApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(create: (_) => MonitorController()),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) => MaterialApp(
          title: 'MikroTik Wi-Fi Tester',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          locale: s.locale,
          supportedLocales: const [Locale('en'), Locale('ru')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeScreen(),
        ),
      ),
    );
  }
}
