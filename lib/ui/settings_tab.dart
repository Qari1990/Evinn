import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../state/app_state.dart';
import '../services/update_service.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Account', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
              const SizedBox(height: 8),
              _row('Signed in as', state.displayName ?? '—'),
              _row('Server', AppConfig.defaultServer),
              _row('Bikes', state.devices.length.toString()),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final d in state.devices)
              ListTile(
                leading: Icon(
                  Icons.directions_bike,
                  color: d.id == state.selectedDeviceId ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(d.name),
                subtitle: Text(d.status),
                trailing: d.id == state.selectedDeviceId ? Icon(Icons.check, color: cs.primary) : null,
                onTap: () => state.selectDevice(d.id),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.system_update, color: cs.primary),
            title: const Text('Check for updates'),
            onTap: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Checking for updates…'), duration: Duration(seconds: 2)),
              );
              await UpdateService.checkAndPrompt(context, silent: false);
            },
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: cs.error),
            title: const Text('Log out'),
            onTap: () => _confirmLogout(context, state),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text('${AppConfig.appName} · v0.1.0 (phase 1)',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  void _confirmLogout(BuildContext context, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              state.logout();
            },
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
