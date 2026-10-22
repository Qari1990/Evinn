import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/traccar.dart';

/// Thin client for the Traccar REST API.
///
/// Uses HTTP Basic auth (email:password base64) on every request, which Traccar
/// accepts on /api/* — this avoids cookie/session juggling on mobile. A later
/// version can switch to a session token + the /api/socket WebSocket for push.
class TraccarApi {
  final String baseUrl; // e.g. https://webapp.elfaelectric.com
  final String username;
  final String password;

  TraccarApi({required String baseUrl, required this.username, required this.password})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'Accept': 'application/json',
      };

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  /// Validates the credentials. Returns the user's display name on success.
  Future<String> login() async {
    final r = await http.get(_u('/api/session'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['name'] ?? username).toString();
    }
    if (r.statusCode == 401) throw Exception('Wrong username or password');
    throw Exception('Login failed (${r.statusCode})');
  }

  Future<List<TraccarDevice>> devices() async {
    final r = await http.get(_u('/api/devices'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load bikes (${r.statusCode})');
    return (jsonDecode(r.body) as List).map((e) => TraccarDevice.fromJson(e)).toList();
  }

  Future<List<TraccarPosition>> positions() async {
    final r = await http.get(_u('/api/positions'), headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load live data (${r.statusCode})');
    return (jsonDecode(r.body) as List).map((e) => TraccarPosition.fromJson(e)).toList();
  }

  /// Trip summaries for a device over a time window.
  Future<List<Map<String, dynamic>>> trips(int deviceId, DateTime from, DateTime to) async {
    final r = await http.get(
      _u('/api/reports/trips', {
        'deviceId': deviceId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      }),
      headers: {..._headers, 'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Could not load trips (${r.statusCode})');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// Raw route points for replaying a trip on the map.
  Future<List<TraccarPosition>> route(int deviceId, DateTime from, DateTime to) async {
    final r = await http.get(
      _u('/api/reports/route', {
        'deviceId': deviceId,
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      }),
      headers: _headers,
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw Exception('Could not load route (${r.statusCode})');
    return (jsonDecode(r.body) as List).map((e) => TraccarPosition.fromJson(e)).toList();
  }
}
