import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/bms.dart';
import '../models/traccar.dart';
import '../services/bms_service.dart';
import '../services/range_estimator.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  BmsData? _bms; // last cached battery reading (for SOC + range)
  DateTime? _bmsTs;

  @override
  void initState() {
    super.initState();
    _loadBms();
  }

  Future<void> _loadBms() async {
    await RangeEstimator.preload();
    final (cached, ts) = await BmsService.loadCached();
    if (!mounted) return;
    setState(() {
      _bms = cached;
      _bmsTs = ts;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pos = state.currentPosition;
    final cs = Theme.of(context).colorScheme;

    if (pos == null) {
      return RefreshIndicator(
        onRefresh: state.refresh,
        child: ListView(children: [
          const SizedBox(height: 120),
          Center(child: Text(state.error ?? 'Waiting for the bike to report…')),
        ]),
      );
    }

    final point = LatLng(pos.latitude, pos.longitude);
    final device = state.selectedDevice;
    // Status like the Elfa app: the tracker's own online/offline flag, backed up
    // by whether it reported very recently.
    final online = device?.status == 'online' ||
        (pos.fixTime != null && DateTime.now().difference(pos.fixTime!).inMinutes < 5);
    final lastUpdate = device?.lastUpdate ?? pos.fixTime;

    return RefreshIndicator(
      onRefresh: () async {
        await state.refresh();
        await _loadBms();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _hero(context, pos, online, lastUpdate),
          if (_rangeModes(pos) != null) ...[
            const SizedBox(height: 12),
            RangeModesCard(modes: _rangeModes(pos)!),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: FlutterMap(
                options: MapOptions(initialCenter: point, initialZoom: 15),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.evinn.app',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: point,
                      width: 26,
                      height: 26,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: cs.primary.withOpacity(.5), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
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
                icon: Icons.battery_full,
                label: 'Battery',
                value: pos.batteryPercent != null ? '${pos.batteryPercent!.round()}%' : '—',
                sub: 'from tracker',
                accent: _battColor(context, pos.batteryPercent),
              ),
              StatCard(icon: Icons.speed, label: 'Speed', value: '${pos.speedKmh.round()} km/h'),
              StatCard(
                icon: pos.ignition ? Icons.power : Icons.power_off,
                label: 'Status',
                value: pos.ignition ? 'ON' : 'Off',
                sub: pos.motion ? 'Moving' : 'Parked',
                accent: pos.ignition ? Colors.green : null,
              ),
              StatCard(
                icon: Icons.add_road,
                label: 'Odometer',
                value: pos.odometerKm != null ? '${pos.odometerKm!.toStringAsFixed(1)} km' : '—',
              ),
              StatCard(
                icon: Icons.thermostat,
                label: 'Temp',
                value: pos.temperature != null ? '${pos.temperature!.round()}°C' : '—',
              ),
              StatCard(
                icon: Icons.timer_outlined,
                label: 'Engine time',
                value: _fmtHours(pos.engineHoursMs),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'
              '${pos.valid ? '' : ' · last valid fix'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 10),
          _allDetails(context, pos),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  /// Every field the tracker reports, for people who want to see everything.
  Widget _allDetails(BuildContext context, TraccarPosition pos) {
    final cs = Theme.of(context).colorScheme;
    final rows = <MapEntry<String, String>>[
      MapEntry('Course', '${pos.course.round()}°'),
      MapEntry('Altitude', '${pos.altitude.round()} m'),
      MapEntry('GPS fix', pos.valid ? 'valid' : 'invalid'),
      if (pos.fixTime != null) MapEntry('Fix time', _fmtTime(pos.fixTime!)),
    ];
    pos.attributes.forEach((k, v) {
      rows.add(MapEntry(_pretty(k), _fmtVal(v)));
    });

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline, size: 18),
        title: const Text('All details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        children: [
          Container(
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: Text(r.key, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
                        Expanded(flex: 5, child: Text(r.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _pretty(String key) {
    // insert spaces before capitals and capitalise first letter: "totalDistance" -> "Total distance"
    final spaced = key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
    final s = spaced.trim();
    return s.isEmpty ? key : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  String _fmtVal(dynamic v) {
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is double) return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return '$v';
  }

  String _fmtTime(DateTime t) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)} ${two(t.day)}/${two(t.month)}';
  }

  /// Top hero: battery charge + estimated range + online/parked at a glance.
  /// SOC comes from the last Bluetooth battery reading when we have one, else
  /// the tracker's battery percentage.
  Widget _hero(BuildContext context, TraccarPosition pos, bool online, DateTime? lastUpdate) {
    final cs = Theme.of(context).colorScheme;
    final bmsSoc = _bms?.soc;
    final trackerPct = pos.batteryPercent?.round();
    final soc = bmsSoc ?? trackerPct;
    final socSource = bmsSoc != null ? 'battery' : (trackerPct != null ? 'tracker' : null);

    final range = RangeEstimator.rangeKm(
      remainingWh: _bms?.remainingWh,
      trackerPercent: bmsSoc == null ? pos.batteryPercent : null,
    );

    Color socColor = soc == null
        ? cs.onSurfaceVariant
        : (soc > 50 ? Colors.green : (soc > 20 ? Colors.orange : cs.error));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [socColor.withOpacity(.16), cs.surfaceContainerLow.withOpacity(0)],
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 86,
                height: 86,
                child: CircularProgressIndicator(
                  value: soc == null ? null : soc / 100.0,
                  strokeWidth: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(socColor),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(soc != null ? '$soc' : '—', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const Text('%', style: TextStyle(fontSize: 11)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (range != null)
                Text('~${range.round()} km left',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800))
              else
                Text(soc != null ? '$soc% charged' : 'No battery data',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _pill(context, online ? Icons.wifi : Icons.wifi_off, online ? 'Online' : 'Offline',
                    online ? Colors.green : cs.error),
                _pill(context, pos.motion ? Icons.directions_bike : Icons.local_parking,
                    pos.motion ? 'Moving' : 'Parked', pos.motion ? Colors.blue : cs.onSurfaceVariant),
                _pill(context, pos.ignition ? Icons.vpn_key : Icons.vpn_key_off,
                    pos.ignition ? 'ACC on' : 'ACC off', pos.ignition ? Colors.green : cs.onSurfaceVariant),
              ]),
              const SizedBox(height: 6),
              Text(
                '${socSource == 'battery' ? 'charge from battery · ${timeAgo(_bmsTs)}' : socSource == 'tracker' ? 'charge from tracker' : ''}'
                '${lastUpdate != null ? '${socSource != null ? '  ·  ' : ''}updated ${timeAgo(lastUpdate)}' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Map<String, double>? _rangeModes(TraccarPosition pos) {
    final bmsSoc = _bms?.soc;
    return RangeEstimator.rangeModes(
      remainingWh: _bms?.remainingWh,
      trackerPercent: bmsSoc == null ? pos.batteryPercent : null,
    );
  }

  Color? _battColor(BuildContext c, double? p) {
    if (p == null) return null;
    if (p > 50) return Colors.green;
    if (p > 20) return Colors.orange;
    return Theme.of(c).colorScheme.error;
  }

  String _fmtHours(double? ms) {
    if (ms == null) return '—';
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
