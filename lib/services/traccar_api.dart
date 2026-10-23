import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/traccar.dart';

/// Thin client for the Traccar REST API.
///
/// Auth: Traccar accepts two login styles and we try both, because some
/// deployments sit behind a reverse proxy / WAF that rejects a plain
/// non-browser form POST with 400/403:
///   1. POST /api/session, form-encoded `email` + `password`
///   2. GET /api/session with HTTP Basic auth
/// Both are sent with browser-like headers (User-Agent, Origin, Referer,
/// X-Requested-With) so a WAF treats them like the real web app. On success we
/// keep the session cookie AND carry Basic auth on every later request, so data
/// calls work even without a cookie.
///
/// Every attempt is appended to [debugLog] (status + a snippet of the response
/// body) so a single screenshot of a failure shows exactly what the server said.
class TraccarApi {
  final String baseUrl; // e.g. https://webapp.elfaelectric.com
  final String username;
  final String password;
  String? _cookie;
  String debugLog = '';

  late final String _basicAuth =
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  TraccarApi({required String baseUrl, required this.username, required this.password})
      : baseUrl = _normalize(baseUrl);

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    return u.replaceAll(RegExp(r'/+$'), '');
  }

  // Headers that make the request look like the Traccar web app in a browser,
  // so a reverse proxy / WAF in front of the server doesn't reject it.
  Map<String, String> get _browser => {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Origin': baseUrl,
        'Referer': '$baseUrl/',
        'X-Requested-With': 'XMLHttpRequest',
      };

  Map<String, String> get _headers => {
        ..._browser,
        'Accept': 'application/json',
        'Authorization': _basicAuth, // works on every Traccar endpoint
        if (_cookie != null) 'Cookie': _cookie!,
      };

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  void _storeCookie(http.Response r) {
    final sc = r.headers['set-cookie'];
    if (sc != null && sc.isNotEmpty) {
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

  void _log(String attempt, http.Response r) {
    final body = r.body.trim();
    final snippet = body.isEmpty
        ? '(empty body)'
        : (body.length > 300 ? '${body.substring(0, 300)}…' : body);
    debugLog += '$attempt -> ${r.statusCode}\n  $snippet\n';
  }

  /// Logs in and returns the user's display name. Throws a message that
  /// includes [debugLog] so failures are self-explanatory.
  Future<String> login() async {
    debugLog = 'Server: $baseUrl\nUser: $username\n\n';
    final uri = _u('/api/session');

    // 1) Form POST with browser headers.
    try {
      final r = await http.post(
        uri,
        headers: {..._browser, 'Accept': 'application/json'},
        body: {'email': username, 'password': password},
      ).timeout(const Duration(seconds: 20));
      _log('POST /api/session (form)', r);
      if (r.statusCode == 200) return _nameFrom(r);
      if (r.statusCode == 401) throw Exception('Wrong username or password\n\n$debugLog');
    } on Exception catch (e) {
      if (e.toString().contains('Wrong username')) rethrow;
      debugLog += 'POST /api/session (form) -> error: $e\n';
    }

    // 2) Basic-auth GET with browser headers.
    try {
      final r = await http.get(
        uri,
        headers: {..._browser, 'Accept': 'application/json', 'Authorization': _basicAuth},
      ).timeout(const Duration(seconds: 20));
      _log('GET /api/session (Basic auth)', r);
      if (r.statusCode == 200) return _nameFrom(r);
      if (r.statusCode == 401) throw Exception('Wrong username or password\n\n$debugLog');
    } on Exception catch (e) {
      if (e.toString().contains('Wrong username')) rethrow;
      debugLog += 'GET /api/session (Basic auth) -> error: $e\n';
    }

    throw Exception('Login failed — server rejected both methods.\n\n$debugLog');
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
