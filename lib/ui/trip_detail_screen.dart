import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../app_config.dart';
import '../models/traccar.dart';
import '../services/range_estimator.dart';
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
  List<TraccarPosition> _routePos = [];
  String? _startAddr;
  String? _endAddr;

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
        _routePos = pts;
        _route = pts.map((p) => LatLng(p.latitude, p.longitude)).toList();
        _loading = false;
      });
      _loadAddresses();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Reverse-geocode the start and end points to readable addresses. We do this
  /// client-side (OpenStreetMap Nominatim) because the Elfa server's own
  /// geocoder is down — that's why the server trips report fails. Failures here
  /// are silent: the trip still shows, just without place names.
  Future<void> _loadAddresses() async {
    final t = widget.trip;
    final s = _latLng(t['startLat'], t['startLon']) ??
        (_route.isNotEmpty ? _route.first : null);
    final e = _latLng(t['endLat'], t['endLon']) ??
        (_route.isNotEmpty ? _route.last : null);
    final sa = s == null ? null : await _reverse(s);
    final ea = e == null ? null : await _reverse(e);
    if (!mounted) return;
    setState(() {
      _startAddr = sa;
      _endAddr = ea;
    });
  }

  Future<String?> _reverse(LatLng p) async {
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18'
          '&lat=${p.latitude}&lon=${p.longitude}');
      final r = await http.get(uri, headers: {
        'User-Agent': 'EVINN/1.0 (evinn-app)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final a = (j['address'] as Map?)?.cast<String, dynamic>() ?? {};
      // Build a short, human address from the most useful parts.
      final parts = <String>[];
      for (final k in ['road', 'neighbourhood', 'suburb', 'village', 'town', 'city']) {
        final v = a[k];
        if (v is String && v.isNotEmpty && !parts.contains(v)) parts.add(v);
        if (parts.length >= 2) break;
      }
      if (parts.isEmpty) {
        final dn = j['display_name'];
        if (dn is String && dn.isNotEmpty) {
          return dn.split(',').take(2).map((e) => e.trim()).join(', ');
        }
        return null;
      }
      return parts.join(', ');
    } catch (_) {
      return null;
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
    final startAddr = _startAddr ?? (t['startAddress'] ?? '').toString();
    final endAddr = _endAddr ?? (t['endAddress'] ?? '').toString();

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
                const SizedBox(height: 14),
                _rideCard(context, distanceKm, avg),
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

  /// Ride mode (from average speed) + how much battery this trip used vs what
  /// that mode should use.
  Widget _rideCard(BuildContext context, double distanceKm, double avgKmh) {
    final cs = Theme.of(context).colorScheme;

    // Mode by average speed, as WAQAR specified.
    final String mode;
    final int modeNo;
    final Color modeColor;
    if (avgKmh < 30) {
      mode = 'Eco';
      modeNo = 1;
      modeColor = Colors.green;
    } else if (avgKmh < 60) {
      mode = 'Normal';
      modeNo = 2;
      modeColor = Colors.blue;
    } else {
      mode = 'Sport';
      modeNo = 3;
      modeColor = Colors.deepOrange;
    }

    // Actual battery drop from the tracker's battery% along the route.
    double? startPct, endPct;
    for (final p in _routePos) {
      final b = p.batteryPercent;
      if (b != null) {
        startPct ??= b;
        endPct = b;
      }
    }
    final actualDrop = (startPct != null && endPct != null) ? (startPct - endPct) : null;

    // Expected drop for this mode: distance × (Wh/km × mode factor) ÷ pack Wh.
    final whKm = RangeEstimator.whPerKmSync * (RangeEstimator.modeFactors[mode] ?? 1.0);
    final fullWh = RangeEstimator.fullAhSync * AppConfig.packNominalV;
    final expectedDrop = fullWh > 0 ? (distanceKm * whKm) / fullWh * 100 : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tune, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('RIDE MODE & BATTERY',
                style: TextStyle(fontSize: 11, letterSpacing: .4, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: modeColor.withOpacity(.15), borderRadius: BorderRadius.circular(20)),
              child: Text('Mode $modeNo · $mode',
                  style: TextStyle(color: modeColor, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Text('avg ${avgKmh.round()} km/h', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _bStat(context, 'Battery used (actual)',
                  actualDrop != null ? '${actualDrop.toStringAsFixed(0)}%' : '—',
                  actualDrop != null && startPct != null && endPct != null
                      ? '${startPct.round()}% → ${endPct.round()}%'
                      : 'tracker battery not logged'),
            ),
            Expanded(
              child: _bStat(context, 'Expected for $mode',
                  expectedDrop != null ? '~${expectedDrop.toStringAsFixed(0)}%' : '—',
                  'est. for ${distanceKm.toStringAsFixed(1)} km'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _bStat(BuildContext context, String label, String value, String sub) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
    ]);
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
