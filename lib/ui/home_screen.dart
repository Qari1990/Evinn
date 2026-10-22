import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../services/update_service.dart';
import 'dashboard_tab.dart';
import 'battery_tab.dart';
import 'trips_tab.dart';
import 'settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Check for a newer build once on launch (best-effort, non-blocking).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkAndPrompt(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tabs = const [DashboardTab(), BatteryTab(), TripsTab(), SettingsTab()];
    final titles = ['Dashboard', 'Battery', 'Trips', 'Settings'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          if (state.devices.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.directions_bike),
              onSelected: state.selectDevice,
              itemBuilder: (_) => state.devices
                  .map((d) => PopupMenuItem(value: d.id, child: Text(d.name)))
                  .toList(),
            ),
          if (_index == 0)
            IconButton(icon: const Icon(Icons.refresh), onPressed: state.refresh),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.battery_charging_full_outlined), selectedIcon: Icon(Icons.battery_charging_full), label: 'Battery'),
          NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route), label: 'Trips'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
