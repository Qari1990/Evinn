import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/traccar.dart';

/// Thin client for the Traccar REST API.
///
/// Auth model (matches how the Elfa web app logs in):
///   POST /api/session with form-encoded `email` + `password` -> 200 + user JSON
///   and a session cookie (JSESSIONID). We keep that cookie and send it on every
///   later request. (A plain GET /api/session with no session returns 404, which
///   is why the first build failed to log in.)
class TraccarApi {
  final String baseUrl; // e.g. https://webapp.elfaelectric.com
  final String username;
  final String password;
  String? _cookie;

  TraccarApi({required String baseUrl, required this.username, required this.password})
      : baseUrl = _normalize(baseUrl);

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (_cookie != null) 'Cookie': _cookie!,
      };

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  void _storeCookie(http.Response r) {
    final sc = r.headers['set-cookie'];
    if (sc != null && sc.isNotEmpty) {
      // Keep just the "NAME=VALUE" part of the first cookie (e.g. JSESSIONID=...).
      _cookie = sc.split(';').first.trim();
    }
  }

  /// Logs in and returns the user's display name. Throws a friendly message.
  Future<String> login() async {
    http.Response r;
    try {
      r = await http.post(
        _u('/api/session'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'email': username, 'password': password},
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      throw Exception('Cannot reach the server. Check the address and your internet.');
    }

    if (r.statusCode == 200) {
      _storeCookie(r);
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return (j['name'] ?? username).toString();
      } catch (_) {
        return username;
      }
    }
    if (r.statusCode == 401) throw Exception('Wrong username or password');
    if (r.statusCode == 404) {
      throw Exception('Login endpoint not found — check the server address (should be like https://webapp.elfaelectric.com).');
    }
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
      headers: _headers,
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
