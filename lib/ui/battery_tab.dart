import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_config.dart';
import '../models/bms.dart';
import '../services/bms_service.dart';
import 'widgets.dart';

/// Deep battery view sourced from the BMS over Bluetooth (JBD/Daly, service FFF0).
class BatteryTab extends StatefulWidget {
  const BatteryTab({super.key});

  @override
  State<BatteryTab> createState() => _BatteryTabState();
}

class _BatteryTabState extends State<BatteryTab> {
  final BmsService _bms = BmsService();
  BmsStatus _status = BmsStatus.idle;
  BmsData? _data;
  String? _error;
  String _log = '';

  @override
  void initState() {
    super.initState();
    _bms.status.listen((s) => setState(() => _status = s));
    _bms.data.listen((d) => setState(() => _data = d));
    _bms.errors.listen((e) => setState(() => _error = e));
    _bms.log.listen((l) => setState(() => _log = l));
  }

  @override
  void dispose() {
    _bms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connected = _status == BmsStatus.connected;
    final busy = _status == BmsStatus.scanning || _status == BmsStatus.connecting;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth, color: connected ? Colors.blue : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_statusText(), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton.tonal(
                onPressed: busy ? null : (connected ? _bms.disconnect : () => _bms.connect()),
                child: Text(busy ? '…' : (connected ? 'Disconnect' : 'Connect')),
              ),
            ]),
          ),
        ),
        if (_error != null && !connected)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          ),
        // BLE debug log — shows exactly which step runs/fails, with a copy button.
        // Stays visible even when connected (so a "connected but no data" case
        // can still be copied).
        if (_log.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('Bluetooth log', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _log));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied — paste it in the chat')),
                          );
                        }
                      },
                    ),
                  ]),
                  SelectableText(_log, style: const TextStyle(fontSize: 12, height: 1.35)),
                ],
              ),
            ),
          ),
        if (_data != null) ..._battery(context, _data!),
        if (_data == null && !busy)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(children: [
              Icon(Icons.battery_unknown, size: 54, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Connect to the bike\'s battery over Bluetooth\nto see per-cell health.',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text('Close the Daly app first — only one connection at a time.',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ]),
          ),
      ],
    );
  }

  String _statusText() {
    switch (_status) {
      case BmsStatus.scanning:
        return 'Scanning for the battery…';
      case BmsStatus.connecting:
        return 'Connecting…';
      case BmsStatus.connected:
        return 'Connected · live';
      case BmsStatus.error:
        return 'Not connected';
      case BmsStatus.idle:
        return 'Battery (Bluetooth)';
    }
  }

  List<Widget> _battery(BuildContext context, BmsData d) {
    final cs = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          StatCard(icon: Icons.battery_charging_full, label: 'Charge', value: d.soc != null ? '${d.soc}%' : '—'),
          StatCard(icon: Icons.bolt, label: 'Pack voltage', value: d.packVoltage != null ? '${d.packVoltage!.toStringAsFixed(2)} V' : '—'),
          StatCard(
            icon: Icons.electric_bolt,
            label: 'Current',
            value: d.current != null ? '${d.current!.toStringAsFixed(1)} A' : '—',
            sub: d.current == null ? null : (d.current! > 0.1 ? 'charging' : d.current! < -0.1 ? 'discharging' : 'idle'),
            accent: d.current == null ? null : (d.current! > 0.1 ? Colors.green : null),
          ),
          StatCard(icon: Icons.power, label: 'Power', value: d.power != null ? '${d.power!.toStringAsFixed(0)} W' : '—'),
          StatCard(
            icon: Icons.thermostat,
            label: 'Temperature',
            value: d.temperatures.isNotEmpty ? '${d.temperatures.map((t) => t.toStringAsFixed(0)).join(', ')}°C' : '—',
          ),
          StatCard(icon: Icons.loop, label: 'Cycles', value: d.cycles?.toString() ?? '—'),
          StatCard(
            icon: Icons.offline_bolt,
            label: 'Charge MOS',
            value: d.chargeMos == null ? '—' : (d.chargeMos! ? 'ON' : 'off'),
            accent: d.chargeMos == true ? Colors.green : null,
          ),
          StatCard(
            icon: Icons.outbound,
            label: 'Discharge MOS',
            value: d.dischargeMos == null ? '—' : (d.dischargeMos! ? 'ON' : 'off'),
            accent: d.dischargeMos == true ? Colors.green : null,
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Cells', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const Spacer(),
        if (d.spreadMv != null)
          Text('spread ${d.spreadMv} mV', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.3,
        children: List.generate(
          d.cellMillivolts.isEmpty ? AppConfig.cellCount : d.cellMillivolts.length,
          (i) => _cell(context, i + 1, d.cellMillivolts.length > i ? d.cellMillivolts[i] : null, d),
        ),
      ),
      const SizedBox(height: 12),
      Text('Updated ${timeAgo(d.updated)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ];
  }

  Widget _cell(BuildContext context, int n, int? mv, BmsData d) {
    final cs = Theme.of(context).colorScheme;
    Color border = cs.outlineVariant;
    if (mv != null && d.maxCellMv != null) {
      if (mv == d.maxCellMv) border = Colors.green;
      if (mv == d.minCellMv) border = cs.error;
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Cell $n', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(mv != null ? '${(mv / 1000).toStringAsFixed(3)}V' : '—',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
