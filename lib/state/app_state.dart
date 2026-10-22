import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/traccar.dart';
import '../services/traccar_api.dart';

/// Central app state: credentials, the selected bike, live position polling.
///
/// Note: credentials are stored in SharedPreferences for phase 1. Before public
/// release, move the password to secure storage (flutter_secure_storage).
class AppState extends ChangeNotifier {
  TraccarApi? _api;
  String? displayName;

  List<TraccarDevice> devices = [];
  int? selectedDeviceId;
  final Map<int, TraccarPosition> positions = {};

  bool loading = false;
  String? error;
  Timer? _poll;

  bool get loggedIn => _api != null;

  TraccarDevice? get selectedDevice {
    if (selectedDeviceId == null) return null;
    try {
      return devices.firstWhere((d) => d.id == selectedDeviceId);
    } catch (_) {
      return devices.isNotEmpty ? devices.first : null;
    }
  }

  TraccarPosition? get currentPosition =>
      selectedDeviceId == null ? null : positions[selectedDeviceId];

  // --- session persistence ------------------------------------------------

  Future<void> tryRestore() async {
    final p = await SharedPreferences.getInstance();
    final server = p.getString('server');
    final user = p.getString('user');
    final pass = p.getString('pass');
    if (server != null && user != null && pass != null) {
      await login(server, user, pass, persist: false);
    }
  }

  Future<void> login(String server, String user, String pass, {bool persist = true}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final api = TraccarApi(baseUrl: server, username: user, password: pass);
      displayName = await api.login();
      _api = api;
      if (persist) {
        final p = await SharedPreferences.getInstance();
        await p.setString('server', server);
        await p.setString('user', user);
        await p.setString('pass', pass);
      }
      await refresh();
      _startPolling();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _poll?.cancel();
    _api = null;
    displayName = null;
    devices = [];
    positions.clear();
    selectedDeviceId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('server');
    await p.remove('user');
    await p.remove('pass');
    notifyListeners();
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    try {
      devices = await api.devices();
      selectedDeviceId ??= devices.isNotEmpty ? devices.first.id : null;
      final pos = await api.positions();
      for (final p in pos) {
        positions[p.deviceId] = p;
      }
      error = null;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
  }

  void selectDevice(int id) {
    selectedDeviceId = id;
    notifyListeners();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(
      Duration(seconds: AppConfig.livePollSeconds),
      (_) => refresh(),
    );
  }

  TraccarApi? get api => _api;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
