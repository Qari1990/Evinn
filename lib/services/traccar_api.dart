import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/traccar.dart';

/// Thin client for the Traccar REST API.
///
/// Auth model (matches how the Elfa web app logs in). Traccar accepts two auth
/// styles, so we try both for robustness:
///   1. POST /api/session with form-encoded `email` + `password` -> 200 + user
///      JSON and a session cookie (JSESSIONID).
///   2. GET /api/session with HTTP Basic auth (Authorization header) -> 200 +
///      user JSON. Traccar honours Basic auth on *every* /api endpoint, so we
///      also keep the Basic header on all later requests as a fallback to the
///      cookie. (A plain GET /api/session with no auth returns 404, which is why
///      the first build failed to log in.)
class TraccarApi {
  final String baseUrl; // e.g. https://webapp.elfaelectric.com
  final String username;
  final String password;
  String? _cookie;
  late final String _basicAuth =
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  TraccarApi({required String baseUrl, required this.username, required this.password})
      : baseUrl = _normalize(baseUrl);

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        // Basic auth works on every Traccar endpoint; keep it alongside the
        // cookie so data calls succeed even if the cookie wasn't captured.
        'Authorization': _basicAuth,
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

  String _nameFrom(http.Response r) {
    _storeCookie(r);
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['name'] ?? username).toString();
    } catch (_) {
      return username;
    }
  }

  /// Logs in and returns the user's display name. Throws a friendly message.
  ///
  /// Strategy: try the form POST first; if the server rejects it (some Traccar
  /// deployments / reverse proxies return 400/404 to the form POST), fall back
  /// to GET /api/session with Basic auth. 401 from either = bad credentials.
  Future<String> login() async {
    final uri = _u('/api/session');
    final attempts = <String>[];

    // 1) Form POST.
    try {
      final r = await http.post(
        uri,
        headers: {'Accept': 'application/json', 'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'email': username, 'password': password},
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return _nameFrom(r);
      if (r.statusCode == 401) throw Exception('Wrong username or password');
      attempts.add('POST $uri -> ${r.statusCode}');
    } on Exception catch (e) {
      if (e.toString().contains('Wrong username')) rethrow;
      attempts.add('POST $uri -> error');
    }

    // 2) Basic-auth GET fallback.
    try {
      final r = await http.get(
        uri,
        headers: {'Accept': 'application/json', 'Authorization': _basicAuth},
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return _nameFrom(r);
      if (r.statusCode == 401) throw Exception('Wrong username or password');
      attempts.add('GET(Basic) $uri -> ${r.statusCode}');
    } on Exception catch (e) {
      if (e.toString().contains('Wrong username')) rethrow;
      attempts.add('GET(Basic) $uri -> error');
    }

    throw Exception('Login failed.\n${attempts.join('\n')}');
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
