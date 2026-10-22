/// Models mirroring the Traccar REST API objects we use.

class TraccarDevice {
  final int id;
  final String name;
  final String uniqueId;
  final String status; // online | offline | unknown
  final DateTime? lastUpdate;

  TraccarDevice({
    required this.id,
    required this.name,
    required this.uniqueId,
    required this.status,
    this.lastUpdate,
  });

  factory TraccarDevice.fromJson(Map<String, dynamic> j) => TraccarDevice(
        id: j['id'] as int,
        name: (j['name'] ?? 'Bike').toString(),
        uniqueId: (j['uniqueId'] ?? '').toString(),
        status: (j['status'] ?? 'unknown').toString(),
        lastUpdate: _dt(j['lastUpdate']),
      );
}

class TraccarPosition {
  final int deviceId;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speedKnots;
  final double course;
  final bool valid;
  final DateTime? fixTime;
  final Map<String, dynamic> attributes;

  TraccarPosition({
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speedKnots,
    required this.course,
    required this.valid,
    required this.fixTime,
    required this.attributes,
  });

  factory TraccarPosition.fromJson(Map<String, dynamic> j) => TraccarPosition(
        deviceId: j['deviceId'] as int,
        latitude: _d(j['latitude']),
        longitude: _d(j['longitude']),
        altitude: _d(j['altitude']),
        speedKnots: _d(j['speed']),
        course: _d(j['course']),
        valid: j['valid'] == true,
        fixTime: _dt(j['fixTime']),
        attributes: (j['attributes'] as Map?)?.cast<String, dynamic>() ?? {},
      );

  double get speedKmh => speedKnots * 1.852;

  // Attribute helpers (gps103/TK103 set, confirmed on WAQAR's bike).
  bool get ignition => attributes['ignition'] == true;
  bool get motion => attributes['motion'] == true;

  /// fuel1 is the tracker's battery percentage (confirmed against the Elfa app).
  double? get batteryPercent => _dn(attributes['fuel1']);
  double? get temperature => _dn(attributes['temp1']);

  /// Odometer in kilometres.
  double? get odometerKm {
    final v = _dn(attributes['totalDistance']);
    return v == null ? null : v / 1000.0;
  }

  /// Engine-on time in milliseconds.
  double? get engineHoursMs => _dn(attributes['hours']);
}

double _d(dynamic v) => v is num ? v.toDouble() : 0.0;
double? _dn(dynamic v) => v is num ? v.toDouble() : null;
DateTime? _dt(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}
