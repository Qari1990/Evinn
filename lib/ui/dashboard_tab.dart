import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/traccar.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key});

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
    final fresh = pos.fixTime != null && DateTime.now().difference(pos.fixTime!).inMinutes < 5;

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 240,
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
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.circle, size: 10, color: fresh ? Colors.green : cs.error),
            const SizedBox(width: 6),
            Text(fresh ? 'Online' : 'Offline', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('Updated ${timeAgo(pos.fixTime)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ]),
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
        ],
      ),
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
