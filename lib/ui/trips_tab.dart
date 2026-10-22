import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _trips = [];
  int _days = 7;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final api = state.api;
    final deviceId = state.selectedDeviceId;
    if (api == null || deviceId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final to = DateTime.now();
      final from = to.subtract(Duration(days: _days));
      final trips = await api.trips(deviceId, from, to);
      trips.sort((a, b) => (b['startTime'] ?? '').toString().compareTo((a['startTime'] ?? '').toString()));
      setState(() => _trips = trips);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Last', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('24h')),
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
              ],
              selected: {_days},
              onSelectionChanged: (s) {
                setState(() => _days = s.first);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: TextStyle(color: cs.error))))
                  : _trips.isEmpty
                      ? const Center(child: Text('No trips in this period'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _trips.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _tripCard(_trips[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _tripCard(Map<String, dynamic> t) {
    final cs = Theme.of(context).colorScheme;
    final start = DateTime.tryParse('${t['startTime']}')?.toLocal();
    final distanceKm = ((t['distance'] ?? 0) as num) / 1000.0;
    final durationMs = (t['duration'] ?? 0) as num;
    final avg = ((t['averageSpeed'] ?? 0) as num) * 1.852;
    final max = ((t['maxSpeed'] ?? 0) as num) * 1.852;
    final fmt = DateFormat('EEE d MMM, HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.route, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(start != null ? fmt.format(start) : 'Trip', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${distanceKm.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 16, children: [
              _chip(Icons.timer_outlined, _fmtDur(durationMs.toInt())),
              _chip(Icons.speed, 'avg ${avg.round()} km/h'),
              _chip(Icons.trending_up, 'max ${max.round()} km/h'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData i, String s) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 14, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(s, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
    ]);
  }

  String _fmtDur(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
