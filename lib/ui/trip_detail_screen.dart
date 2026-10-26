import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traccar.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Full details for one trip: a map with the ridden route plus the trip's stats.
class TripDetailScreen extends StatefulWidget {
  final Map<String, dynamic> trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  bool _loading = true;
  String? _error;
  List<LatLng> _route = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoute());
  }

  Future<void> _loadRoute() async {
    final state = context.read<AppState>();
    final api = state.api;
    final deviceId = state.selectedDeviceId;
    final from = DateTime.tryParse('${widget.trip['startTime']}');
    final to = DateTime.tryParse('${widget.trip['endTime']}');
    if (api == null || deviceId == null || from == null || to == null) {
      setState(() {
        _loading = false;
        _error = 'Route not available for this trip.';
      });
      return;
    }
    try {
      final pts = await api.route(deviceId, from, to);
      setState(() {
        _route = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    final cs = Theme.of(context).colorScheme;
    final start = DateTime.tryParse('${t['startTime']}')?.toLocal();
    final end = DateTime.tryParse('${t['endTime']}')?.toLocal();
    final distanceKm = ((t['distance'] ?? 0) as num) / 1000.0;
    final durationMs = (t['duration'] ?? 0) as num;
    final avg = ((t['averageSpeed'] ?? 0) as num) * 1.852;
    final max = ((t['maxSpeed'] ?? 0) as num) * 1.852;
    final startAddr = (t['startAddress'] ?? '').toString();
    final endAddr = (t['endAddress'] ?? '').toString();

    final startPt = _latLng(t['startLat'], t['startLon']);
    final endPt = _latLng(t['endLat'], t['endLon']);
    final center = startPt ?? (_route.isNotEmpty ? _route.first : const LatLng(0, 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: ListView(
        children: [
          SizedBox(
            height: 280,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.evinn.app',
                      ),
                      if (_route.length > 1)
                        PolylineLayer(polylines: [
                          Polyline(points: _route, strokeWidth: 4, color: cs.primary),
                        ]),
                      MarkerLayer(markers: [
                        if (startPt != null) _marker(startPt, Colors.green),
                        if (endPt != null) _marker(endPt, cs.error),
                      ]),
                    ],
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                if (start != null)
                  Text(DateFormat('EEEE d MMM, HH:mm').format(start),
                      style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.7,
                  children: [
                    StatCard(icon: Icons.timer_outlined, label: 'Duration', value: _fmtDur(durationMs.toInt())),
                    StatCard(icon: Icons.speed, label: 'Avg speed', value: '${avg.round()} km/h'),
                    StatCard(icon: Icons.trending_up, label: 'Top speed', value: '${max.round()} km/h'),
                    StatCard(
                      icon: Icons.schedule,
                      label: 'Ended',
                      value: end != null ? DateFormat('HH:mm').format(end) : '—',
                    ),
                  ],
                ),
                if (startAddr.isNotEmpty || endAddr.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  if (startAddr.isNotEmpty) _place(context, Icons.trip_origin, Colors.green, 'From', startAddr),
                  if (endAddr.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _place(context, Icons.place, cs.error, 'To', endAddr),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _place(BuildContext context, IconData icon, Color color, String label, String addr) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          Text(addr, style: const TextStyle(fontSize: 14)),
        ]),
      ),
    ]);
  }

  Marker _marker(LatLng p, Color color) => Marker(
        point: p,
        width: 20,
        height: 20,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      );

  LatLng? _latLng(dynamic lat, dynamic lon) {
    if (lat is num && lon is num && (lat != 0 || lon != 0)) {
      return LatLng(lat.toDouble(), lon.toDouble());
    }
    return null;
  }

  String _fmtDur(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
