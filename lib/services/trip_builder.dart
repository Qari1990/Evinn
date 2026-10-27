import 'dart:math';
import '../models/traccar.dart';

/// Builds trip summaries from raw position history, so we don't depend on the
/// Traccar server's /api/reports/trips — that report crashes (HTTP 400) on the
/// Elfa server because its reverse-geocoder host (LocationIQ) is unreachable.
///
/// A trip is a continuous run of movement. Brief stops (under [stopGapMin]) are
/// merged into one trip; a longer stop, or a gap in fixes over [maxGapMin],
/// ends it. Each trip is returned in the same shape the Traccar trips report
/// uses (distance in metres, speeds in knots, ISO times) so the UI is unchanged.
class TripBuilder {
  static const double movingKmh = 3.0; // below this (and not in motion) = stopped
  static const int stopGapMin = 3; // stationary this long ends a trip
  static const int maxGapMin = 12; // a fix gap this long ends a trip
  static const double minTripKm = 0.3;
  static const int minTripSec = 60;

  static List<Map<String, dynamic>> build(List<TraccarPosition> positions) {
    final pts = positions.where((p) => p.fixTime != null).toList()
      ..sort((a, b) => a.fixTime!.compareTo(b.fixTime!));

    final trips = <Map<String, dynamic>>[];
    final cur = <TraccarPosition>[];

    void close() {
      final t = _summarise(cur);
      if (t != null) trips.add(t);
      cur.clear();
    }

    for (final p in pts) {
      final moving = p.speedKmh >= movingKmh || p.motion;
      if (cur.isNotEmpty) {
        final gap = p.fixTime!.difference(cur.last.fixTime!).inMinutes;
        if (gap >= maxGapMin) close();
      }
      if (moving) {
        cur.add(p);
      } else if (cur.isNotEmpty) {
        final stoppedFor = p.fixTime!.difference(cur.last.fixTime!).inMinutes;
        if (stoppedFor >= stopGapMin) close();
        // else: a brief stop — keep the trip open, drop this stationary point
      }
    }
    close();

    // newest first
    trips.sort((a, b) => (b['startTime'] as String).compareTo(a['startTime'] as String));
    return trips;
  }

  static Map<String, dynamic>? _summarise(List<TraccarPosition> pts) {
    if (pts.length < 2) return null;
    final start = pts.first.fixTime!;
    final end = pts.last.fixTime!;
    final durSec = end.difference(start).inSeconds;
    if (durSec < minTripSec) return null;

    double distM = 0;
    double maxKnots = 0;
    for (var i = 0; i < pts.length; i++) {
      if (pts[i].speedKnots > maxKnots) maxKnots = pts[i].speedKnots;
      if (i > 0) {
        distM += _haversine(pts[i - 1].latitude, pts[i - 1].longitude, pts[i].latitude, pts[i].longitude);
      }
    }
    if (distM < minTripKm * 1000) return null;

    final mps = distM / durSec; // metres per second
    final avgKnots = mps / 0.514444;

    return {
      'distance': distM,
      'duration': durSec * 1000,
      'averageSpeed': avgKnots,
      'maxSpeed': maxKnots,
      'startTime': start.toUtc().toIso8601String(),
      'endTime': end.toUtc().toIso8601String(),
      'startLat': pts.first.latitude,
      'startLon': pts.first.longitude,
      'endLat': pts.last.latitude,
      'endLon': pts.last.longitude,
    };
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180.0;
}
