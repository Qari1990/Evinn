import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';
import '../models/bms.dart';
import 'charge_log.dart';
import 'daly_protocol.dart';

enum BmsStatus { idle, scanning, connecting, connected, error }

/// Connects to the bike's Daly BMS over BLE (service FFF0, notify FFF1, write
/// FFF2) and streams parsed battery snapshots. Caches the last reading so it can
/// be shown (with a timestamp) when disconnected.
class BmsService {
  static final Guid serviceFff0 = Guid('0000fff0-0000-1000-8000-00805f9b34fb');

  final _statusCtrl = StreamController<BmsStatus>.broadcast();
  final _dataCtrl = StreamController<BmsData>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  Stream<BmsStatus> get status => _statusCtrl.stream;
  Stream<BmsData> get data => _dataCtrl.stream;
  Stream<String> get errors => _errorCtrl.stream;
  Stream<String> get log => _logCtrl.stream;

  // A short rolling log (last N lines) for the collapsible "Bluetooth log".
  final List<String> _logLines = [];
  static const int _maxLogLines = 18;
  String get debugLog => _logLines.join('\n');
  bool _sawData = false;

  final _daly = DalyProtocol();
  final _chargeTracker = ChargeTracker();
  BmsData _snapshot = BmsData();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _write;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  StreamSubscription? _connSub;
  Timer? _pollTimer;
  DateTime _lastCache = DateTime.fromMillisecondsSinceEpoch(0);

  BmsData get snapshot => _snapshot;

  void _d(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    _logLines.add('[$t] $line');
    while (_logLines.length > _maxLogLines) {
      _logLines.removeAt(0);
    }
    _logCtrl.add(debugLog);
  }

  // ---- last-reading cache -------------------------------------------------

  static const _kLast = 'bms_last';
  static const _kLastTs = 'bms_last_ts';

  Future<void> _cache(BmsData d) async {
    // Throttle writes to ~once every 5s.
    if (DateTime.now().difference(_lastCache).inSeconds < 5) return;
    _lastCache = DateTime.now();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLast, jsonEncode(d.toJson()));
      await p.setInt(_kLastTs, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Load the last cached reading and when it was taken.
  static Future<(BmsData?, DateTime?)> loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_kLast);
      final ts = p.getInt(_kLastTs);
      if (s == null) return (null, null);
      return (
        BmsData.fromJson(jsonDecode(s) as Map<String, dynamic>),
        ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
      );
    } catch (_) {
      return (null, null);
    }
  }

  // ---- connect ------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> connect({String? remoteId}) async {
    _logLines.clear();
    _sawData = false;
    try {
      _d('Requesting permissions…');
      if (!await _ensurePermissions()) {
        _d('Permissions denied');
        _errorCtrl.add('Bluetooth/Location permission denied — allow Nearby devices & Location in app settings.');
        _statusCtrl.add(BmsStatus.error);
        return;
      }
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _d('Bluetooth is OFF');
        _errorCtrl.add('Please turn on Bluetooth');
        _statusCtrl.add(BmsStatus.error);
        return;
      }
      _d('Bluetooth ON · scanning…');

      _statusCtrl.add(BmsStatus.scanning);
      final wantMac = (remoteId ?? AppConfig.bmsMac).trim().toUpperCase();
      final wantName = AppConfig.bmsName.trim().toLowerCase();
      final completer = Completer<BluetoothDevice>();
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final id = r.device.remoteId.str.toUpperCase();
          final name = (r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : r.advertisementData.advName)
              .toLowerCase();
          final matchId = wantMac.isNotEmpty && id == wantMac;
          final matchName = wantName.isNotEmpty && name == wantName;
          final matchSvc = r.advertisementData.serviceUuids
              .map((g) => g.str.toLowerCase())
              .contains(serviceFff0.str.toLowerCase());
          if (matchId || matchName || matchSvc) {
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      final device = await completer.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () => throw Exception(
            'Battery not found. Check: Bluetooth on, phone next to the bike, and '
            'the Daly app fully closed (it holds the connection).'),
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _d('Found the battery · connecting…');

      _statusCtrl.add(BmsStatus.connecting);
      _device = device;
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && _sawData) {
          _d('Disconnected');
        }
      });

      try {
        await device.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      } catch (e) {
        await Future.delayed(const Duration(seconds: 2));
        await device.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      }

      await Future.delayed(const Duration(milliseconds: 400));
      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase().contains('fff0'),
        orElse: () => throw Exception('Battery BLE service not found'),
      );
      final notify = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().contains('fff1'),
          orElse: () => throw Exception('Notify characteristic not found'));
      _write = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().contains('fff2'),
          orElse: () => throw Exception('Write characteristic not found'));

      await notify.setNotifyValue(true);
      _daly.reset();
      _notifySub = notify.onValueReceived.listen((chunk) {
        final parsed = _daly.addChunk(chunk);
        if (parsed != null) {
          _snapshot = _snapshot.merge(parsed);
          _dataCtrl.add(_snapshot);
          _cache(_snapshot);
          _chargeTracker.record(_snapshot);
          if (!_sawData) {
            _sawData = true;
            _d('Receiving live data ✓');
          }
        }
      });

      _statusCtrl.add(BmsStatus.connected);
      _d('Connected');
      await _poll();
      _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
    } catch (e) {
      _d('Error: ${_short(e)}');
      _errorCtrl.add(e.toString().replaceFirst('Exception: ', ''));
      _statusCtrl.add(BmsStatus.error);
      await disconnect();
    }
  }

  static String _short(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  /// Poll the full Daly command set so every field stays current.
  Future<void> _poll() async {
    final w = _write;
    if (w == null) return;
    final wo = w.properties.writeWithoutResponse && !w.properties.write;
    for (final (_, cmd) in DalyProtocol.pollSet) {
      try {
        await w.write(cmd, withoutResponse: wo);
      } catch (_) {
        try {
          await w.write(cmd, withoutResponse: !wo);
        } catch (_) {}
      }
      await Future.delayed(const Duration(milliseconds: 220));
    }
  }

  Future<void> disconnect() async {
    _chargeTracker.flush();
    _pollTimer?.cancel();
    await _notifySub?.cancel();
    await _scanSub?.cancel();
    await _connSub?.cancel();
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _write = null;
    _statusCtrl.add(BmsStatus.idle);
  }

  void dispose() {
    disconnect();
    _statusCtrl.close();
    _dataCtrl.close();
    _errorCtrl.close();
    _logCtrl.close();
  }
}
