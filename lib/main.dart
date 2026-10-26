import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_config.dart';
import 'services/range_estimator.dart';
import 'state/app_state.dart';
import 'ui/login_screen.dart';
import 'ui/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RangeEstimator.preload(); // warm the learned Wh/km cache (best-effort)
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..tryRestore(),
      child: const EvBikeApp(),
    ),
  );
}

class EvBikeApp extends StatelessWidget {
  const EvBikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(seedColor: AppConfig.seedColor);
    final darkScheme = ColorScheme.fromSeed(seedColor: AppConfig.seedColor, brightness: Brightness.dark);
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorScheme: lightScheme),
      darkTheme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
      themeMode: ThemeMode.system,
      home: Consumer<AppState>(
        builder: (_, state, __) => state.loggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
