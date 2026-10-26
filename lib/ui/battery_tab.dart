import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_config.dart';
import '../models/bms.dart';
import '../services/bms_service.dart';
import 'widgets.dart';

/// Deep battery view sourced from the Daly BMS over Bluetooth (service FFF0).
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
  DateTime? _lastConnected; // timestamp of the cached reading

  @override
  void initState() {
    super.initState();
    _bms.status.listen((s) => setState(() => _status = s));
    _bms.data.listen((d) => setState(() {
          _data = d;
          _lastConnected = DateTime.now();
        }));
    _bms.errors.listen((e) => setState(() => _error = e));
    _bms.log.listen((l) => setState(() => _log = l));
    _loadCached();
  }

  Future<void> _loadCached() async {
    final (cached, ts) = await BmsService.loadCached();
    if (!mounted || cached == null) return;
    if (_data == null) {
      setState(() {
        _data = cached;
        _lastConnected = ts;
      });
    }
  }

  @override
  void dispose() {
    _bms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == BmsStatus.connected;
    final busy = _status == BmsStatus.scanning || _status == BmsStatus.connecting;
    final d = _data;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _connectCard(context, connected, busy),
        if (!connected && d != null && d.hasAnyData) _lastReadingBanner(context),
        if (_error != null && !connected)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (d != null && d.hasAnyData) ..._battery(context, d, connected),
        if (d == null && !busy) _emptyState(context),
        if (_log.isNotEmpty) _logTile(context),
      ],
    );
  }

  // ---- header ------------------------------------------------------------

  Widget _connectCard(BuildContext context, bool connected, bool busy) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: connected ? Colors.blue : cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(_statusText(), style: const TextStyle(fontWeight: FontWeight.w600))),
          FilledButton.tonal(
            onPressed: busy ? null : (connected ? _bms.disconnect : () => _bms.connect()),
            child: Text(busy ? '…' : (connected ? 'Disconnect' : 'Connect')),
          ),
        ]),
      ),
    );
  }

  Widget _lastReadingBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withOpacity(.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.history, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Last reading — ${timeAgo(_lastConnected)} · connect to refresh',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ),
      ]),
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

  // ---- battery body ------------------------------------------------------

  List<Widget> _battery(BuildContext context, BmsData d, bool live) {
    final cs = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 12),
      _hero(context, d),
      if (d.alarms.isNotEmpty) ...[
        const SizedBox(height: 12),
        _alarmBanner(context, d.alarms),
      ],
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          StatCard(
            icon: Icons.electric_bolt,
            label: 'Current',
            value: d.current != null ? '${d.current!.toStringAsFixed(1)} A' : '—',
            sub: d.state,
            accent: d.current == null ? null : (d.current! > 0.3 ? Colors.green : null),
          ),
          StatCard(icon: Icons.power, label: 'Power', value: d.power != null ? '${d.power!.toStringAsFixed(0)} W' : '—'),
          StatCard(
            icon: Icons.thermostat,
            label: 'Temperature',
            value: d.temperatures.isNotEmpty
                ? '${d.temperatures.map((t) => t.toStringAsFixed(0)).join(', ')}°C'
                : '—',
            sub: (d.maxTempC != null && d.minTempC != null) ? 'range ${d.minTempC!.toStringAsFixed(0)}–${d.maxTempC!.toStringAsFixed(0)}°C' : null,
          ),
          StatCard(
            icon: Icons.battery_std,
            label: 'Capacity left',
            value: d.remainingAh != null ? '${d.remainingAh!.toStringAsFixed(1)} Ah' : '—',
          ),
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
          StatCard(
            icon: Icons.power_settings_new,
            label: 'Charger',
            value: d.chargerConnected == null ? '—' : (d.chargerConnected! ? 'Plugged in' : 'No'),
            accent: d.chargerConnected == true ? Colors.green : null,
          ),
          StatCard(
            icon: Icons.electrical_services,
            label: 'Load',
            value: d.loadConnected == null ? '—' : (d.loadConnected! ? 'On' : 'Off'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Cells', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const Spacer(),
        if (d.avgCellMv != null)
          Text('avg ${(d.avgCellMv! / 1000).toStringAsFixed(3)} V', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        if (d.spreadMv != null) ...[
          const SizedBox(width: 10),
          Text('spread ${d.spreadMv} mV',
              style: TextStyle(color: d.spreadMv! > 50 ? cs.error : cs.onSurfaceVariant, fontSize: 12)),
        ],
      ]),
      if (d.balancingCells.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Balancing: cell ${d.balancingCells.join(', ')}',
              style: TextStyle(color: Colors.blue, fontSize: 12)),
        ),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.25,
        children: List.generate(
          d.cellMillivolts.isEmpty ? AppConfig.cellCount : d.cellMillivolts.length,
          (i) => _cell(context, i + 1, d.cellMillivolts.length > i ? d.cellMillivolts[i] : null, d),
        ),
      ),
      const SizedBox(height: 12),
      Text('Updated ${timeAgo(d.updated)}${live ? ' · live' : ''}',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ];
  }

  Widget _hero(BuildContext context, BmsData d) {
    final cs = Theme.of(context).colorScheme;
    final soc = d.soc;
    Color socColor = soc == null
        ? cs.onSurfaceVariant
        : (soc > 50 ? Colors.green : (soc > 20 ? Colors.orange : cs.error));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 92,
                height: 92,
                child: CircularProgressIndicator(
                  value: soc == null ? null : soc / 100.0,
                  strokeWidth: 9,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(socColor),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(soc != null ? '$soc' : '—', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const Text('%', style: TextStyle(fontSize: 12)),
              ]),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.packVoltage != null ? '${d.packVoltage!.toStringAsFixed(1)} V' : '—',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(
                  d.state == 'charging'
                      ? Icons.bolt
                      : (d.state == 'discharging' ? Icons.south : Icons.pause),
                  size: 15,
                  color: d.state == 'charging' ? Colors.green : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  d.state == null
                      ? 'pack voltage'
                      : (d.state == 'charging'
                          ? 'Charging'
                          : (d.state == 'discharging' ? 'Discharging' : 'Idle')),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _alarmBanner(BuildContext context, List<String> alarms) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(alarms.join(' · '),
              style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _cell(BuildContext context, int n, int? mv, BmsData d) {
    final cs = Theme.of(context).colorScheme;
    Color border = cs.outlineVariant;
    final balancing = d.balancingCells.contains(n);
    if (mv != null && d.maxCellMv != null) {
      if (mv == d.maxCellMv) border = Colors.green;
      if (mv == d.minCellMv) border = cs.error;
    }
    if (balancing) border = Colors.blue;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Cell $n', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          if (balancing) ...[
            const SizedBox(width: 3),
            const Icon(Icons.sync, size: 10, color: Colors.blue),
          ],
        ]),
        const SizedBox(height: 2),
        Text(mv != null ? '${(mv / 1000).toStringAsFixed(3)}V' : '—',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(children: [
        Icon(Icons.battery_unknown, size: 54, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text("Connect to the bike's battery over Bluetooth\nto see per-cell health.",
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text('Close the Daly app first — only one connection at a time.',
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }

  Widget _logTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('Bluetooth log', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _log));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      }
                    },
                  ),
                ),
                SelectableText(_log, style: const TextStyle(fontSize: 12, height: 1.35)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
