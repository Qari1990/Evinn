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

  /// Logs in and returns the user's display name. Tries several request
  /// encodings because the server rejected a plain form POST with an SQL
  /// "parameter 1 null" error (the email field wasn't landing). The first one
  /// that returns 200 wins; every attempt is recorded in [debugLog].
  Future<String> login() async {
    debugLog = 'Server: $baseUrl\nUser: $username\n\n';
    final uri = _u('/api/session');
    final formHeaders = {
      ..._browser,
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    final rawForm =
        'email=${Uri.encodeQueryComponent(username)}&password=${Uri.encodeQueryComponent(password)}';

    // Elfa customised their session endpoint (the server trace shows an
    // OverrideFilter and an SQL "parameter 1 null"), so it likely reads a
    // different identifier field than `email`. Send every likely field name at
    // once — the server picks whichever one it declares and ignores the rest.
    final multiId = {
      'email': username,
      'username': username,
      'phone': username,
      'mobile': username,
      'login': username,
      'password': password,
    };

    // Each attempt: (label, function returning the Response).
    final attempts = <(String, Future<http.Response> Function())>[
      // E: form POST with all likely identifier field names (most likely fix).
      ('E POST form (all id fields)', () => http.post(uri,
          headers: {..._browser, 'Accept': 'application/json'},
          body: multiId)),
      // A: form POST, Map body (http sets the urlencoded content-type).
      ('A POST form (map)', () => http.post(uri,
          headers: {..._browser, 'Accept': 'application/json'},
          body: {'email': username, 'password': password})),
      // B: form POST, explicit raw urlencoded string body.
      ('B POST form (raw string)', () => http.post(uri, headers: formHeaders, body: rawForm)),
      // C: form fields in the query string, empty body.
      ('C POST query string', () => http.post(
          _u('/api/session', {'email': username, 'password': password}),
          headers: formHeaders)),
      // D: JSON body.
      ('D POST json', () => http.post(uri,
          headers: {..._browser, 'Accept': 'application/json', 'Content-Type': 'application/json'},
          body: jsonEncode({'email': username, 'password': password}))),
    ];

    for (final (label, run) in attempts) {
      try {
        final r = await run().timeout(const Duration(seconds: 20));
        _log(label, r);
        if (r.statusCode == 200) {
          debugLog += '\n✓ worked: $label\n';
          return _nameFrom(r);
        }
        if (r.statusCode == 401) {
          throw Exception('Wrong username or password ($label)\n\n$debugLog');
        }
      } on Exception catch (e) {
        if (e.toString().contains('Wrong username')) rethrow;
        debugLog += '$label -> error: $e\n';
      }
    }

    throw Exception('Login failed — none of the request formats worked.\n\n$debugLog');
  }

  /// GET that transparently re-logs-in and retries once if the session has
  /// expired (Traccar drops the cookie after a while, which was making live
  /// data freeze and reports come back empty until the app was restarted).
  Future<http.Response> _authedGet(String path, [Map<String, dynamic>? q, Duration timeout = const Duration(seconds: 20)]) async {
    var r = await http.get(_u(path, q), headers: _headers).timeout(timeout);
    if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 404) {
      try {
        await login(); // refresh the session cookie
        r = await http.get(_u(path, q), headers: _headers).timeout(timeout);
      } catch (_) {
        // keep the original response if re-login itself failed
      }
    }
    return r;
  }

  Future<List<TraccarDevice>> devices() async {
    final r = await _authedGet('/api/devices');
    if (r.statusCode != 200) throw Exception('Could not load bikes (${r.statusCode})');
    return (jsonDecode(r.body) as List).map((e) => TraccarDevice.fromJson(e)).toList();
  }

  Future<List<TraccarPosition>> positions() async {
    final r = await _authedGet('/api/positions');
    if (r.statusCode != 200) throw Exception('Could not load live data (${r.statusCode})');
    return (jsonDecode(r.body) as List).map((e) => TraccarPosition.fromJson(e)).toList();
  }

  /// Traccar's report endpoints are strict about the time format. Match exactly
  /// what the web app sends — millisecond precision + 'Z' — because Dart's
  /// default toIso8601String() can emit microseconds, which the server rejects
  /// with a 400.
  static String _iso(DateTime d) {
    final u = d.toUtc();
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${u.year}-${p(u.month)}-${p(u.day)}'
        'T${p(u.hour)}:${p(u.minute)}:${p(u.second)}.${p(u.millisecond, 3)}Z';
  }

  static String _bodySnippet(http.Response r) {
    final b = r.body.trim();
    if (b.isEmpty) return '';
    return b.length > 160 ? '${b.substring(0, 160)}…' : b;
  }

  /// Trip summaries for a device over a time window.
  Future<List<Map<String, dynamic>>> trips(int deviceId, DateTime from, DateTime to) async {
    final r = await _authedGet('/api/reports/trips', {
      'deviceId': deviceId,
      'from': _iso(from),
      'to': _iso(to),
    }, const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('Could not load trips (${r.statusCode})${_bodySnippet(r).isEmpty ? '' : ': ${_bodySnippet(r)}'}');
    }
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  /// Raw route points for replaying a trip on the map.
  Future<List<TraccarPosition>> route(int deviceId, DateTime from, DateTime to) async {
    final r = await _authedGet('/api/reports/route', {
      'deviceId': deviceId,
      'from': _iso(from),
      'to': _iso(to),
    }, const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw Exception('Could not load route (${r.statusCode})${_bodySnippet(r).isEmpty ? '' : ': ${_bodySnippet(r)}'}');
    }
    return (jsonDecode(r.body) as List).map((e) => TraccarPosition.fromJson(e)).toList();
  }
}
