import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/monitor_controller.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

void main() {
  runApp(const WifiApkApp());
}

class WifiApkApp extends StatelessWidget {
  const WifiApkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MonitorController(),
      child: MaterialApp(
        title: 'MikroTik Wi-Fi Tester',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const HomeScreen(),
      ),
    );
  }
}
