import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app_config.dart';
import '../models/bms.dart';
import 'jbd_protocol.dart';
import 'daly_protocol.dart';

enum BmsStatus { idle, scanning, connecting, connected, error }

/// Connects to the JBD/Daly BMS over BLE (service FFF0, notify FFF1, write FFF2)
/// and streams parsed battery snapshots.
class BmsService {
  static final Guid serviceFff0 = Guid('0000fff0-0000-1000-8000-00805f9b34fb');
  static final Guid charNotifyFff1 = Guid('0000fff1-0000-1000-8000-00805f9b34fb');
  static final Guid charWriteFff2 = Guid('0000fff2-0000-1000-8000-00805f9b34fb');

  final _statusCtrl = StreamController<BmsStatus>.broadcast();
  final _dataCtrl = StreamController<BmsData>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  Stream<BmsStatus> get status => _statusCtrl.stream;
  Stream<BmsData> get data => _dataCtrl.stream;
  Stream<String> get errors => _errorCtrl.stream;
  Stream<String> get log => _logCtrl.stream;

  /// Human-readable trace of the last connect attempt (for the on-screen
  /// "Copy details" button, same idea as the login debug log).
  String debugLog = '';
  StreamSubscription? _connSub;

  void _d(String line) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    debugLog += '[$t] $line\n';
    _logCtrl.add(debugLog);
  }

  final _jbd = JbdProtocol();
  final _daly = DalyProtocol();
  BmsData _snapshot = BmsData();
  BluetoothDevice? _device;
  BluetoothCharacteristic? _write;
  StreamSubscription? _notifySub;
  StreamSubscription? _scanSub;
  Timer? _pollTimer;

  BmsData get snapshot => _snapshot;

  Future<bool> _ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  /// Scans for the bike's BMS (filtered by the FFF0 service) and connects to the
  /// first match. Optionally match a known [remoteId] (MAC) for a saved bike.
  Future<void> connect({String? remoteId}) async {
    debugLog = '';
    try {
      _d('Requesting permissions…');
      if (!await _ensurePermissions()) {
        _d('Permissions denied');
        _errorCtrl.add('Bluetooth/Location permission denied — allow Nearby devices & Location in app settings.');
        _statusCtrl.add(BmsStatus.error);
        return;
      }
      _d('Permissions OK');
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _d('Adapter is OFF');
        _errorCtrl.add('Please turn on Bluetooth');
        _statusCtrl.add(BmsStatus.error);
        return;
      }
      _d('Bluetooth adapter ON');

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
          // Fallback: some boards DO advertise the FFF0 service.
          final matchSvc = r.advertisementData.serviceUuids
              .map((g) => g.str.toLowerCase())
              .contains(serviceFff0.str.toLowerCase());
          if (matchId || matchName || matchSvc) {
            final how = matchId ? 'MAC' : (matchName ? 'name' : 'FFF0 adv');
            _d('Found "${name.isEmpty ? '(no name)' : name}" $id (by $how)');
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });
      // Scan everything (no service filter): JBD/Daly boards usually don't
      // advertise FFF0, so a service-filtered scan would never see them.
      _d('Scanning (looking for "${AppConfig.bmsName}" / ${AppConfig.bmsMac})…');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      final device = await completer.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () => throw Exception(
            'BMS not found. Check: Bluetooth on, phone next to the bike, and the '
            'Daly/BMS app fully closed (it holds the connection). Looking for '
            '"${AppConfig.bmsName}" / ${AppConfig.bmsMac}.'),
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();

      _statusCtrl.add(BmsStatus.connecting);
      _device = device;

      // Watch the live connection state so a drop (e.g. Android GATT 133, or the
      // Daly app grabbing the link) shows up in the log instead of a silent fail.
      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) => _d('Connection state: $s'));

      // Connect with one retry — Android often throws status 133 on the first try.
      _d('Connecting to ${device.remoteId.str}…');
      try {
        await device.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      } catch (e) {
        _d('First connect failed ($e) — retrying once…');
        await Future.delayed(const Duration(seconds: 2));
        await device.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      }
      _d('Connected. Discovering services…');

      await Future.delayed(const Duration(milliseconds: 400)); // let the stack settle
      final services = await device.discoverServices();
      _d('Discovered ${services.length} services: ${services.map((s) => s.uuid.str.split('-').first).join(', ')}');
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase().contains('fff0'),
        orElse: () => throw Exception('BMS service FFF0 not found in ${services.length} services'),
      );
      final notify = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().contains('fff1'),
          orElse: () => throw Exception('Notify char FFF1 not found'));
      _write = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().contains('fff2'),
          orElse: () => throw Exception('Write char FFF2 not found'));
      _d('FFF0/FFF1/FFF2 found (write props: wResp=${_write!.properties.write}, woResp=${_write!.properties.writeWithoutResponse})');

      await notify.setNotifyValue(true);
      _d('Notifications enabled on FFF1');
      _jbd.reset();
      _daly.reset();
      _notifySub = notify.onValueReceived.listen((chunk) {
        _d('RX ${chunk.length}B: ${_hex(chunk)}');
        // Route by frame header: JBD frames start 0xDD, Daly frames start 0xA5.
        // Feed the matching parser (both are tried so we auto-detect which
        // protocol this board actually speaks).
        final parsed = _jbd.addChunk(chunk) ?? _daly.addChunk(chunk);
        if (parsed != null) {
          _snapshot = _snapshot.merge(parsed);
          _dataCtrl.add(_snapshot);
          _d('Parsed a frame → data updated');
        }
      });

      _statusCtrl.add(BmsStatus.connected);
      _d('Connected — requesting battery data');
      await _poll();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      _d('ERROR: $e');
      _errorCtrl.add(e.toString());
      _statusCtrl.add(BmsStatus.error);
      await disconnect();
    }
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

  Future<void> _send(BluetoothCharacteristic w, List<int> cmd, String label) async {
    try {
      final wo = w.properties.writeWithoutResponse && !w.properties.write;
      await w.write(cmd, withoutResponse: wo);
      _d('TX $label [${_hex(cmd)}]');
    } catch (e) {
      // Try the other write type if the first is rejected.
      try {
        await w.write(cmd, withoutResponse: !w.properties.writeWithoutResponse);
        _d('TX $label (fallback write) [${_hex(cmd)}]');
      } catch (e2) {
        _d('TX $label FAILED: $e2');
      }
    }
  }

  /// Poll both protocols — the board speaks one of them; whichever answers wins.
  Future<void> _poll() async {
    final w = _write;
    if (w == null) return;
    // JBD / Xiaoxiang
    await _send(w, JbdProtocol.readBasicInfo(), 'JBD basic');
    await Future.delayed(const Duration(milliseconds: 350));
    await _send(w, JbdProtocol.readCellVolts(), 'JBD cells');
    await Future.delayed(const Duration(milliseconds: 350));
    // Classic Daly
    await _send(w, DalyProtocol.soc(), 'Daly 0x90');
    await Future.delayed(const Duration(milliseconds: 350));
    await _send(w, DalyProtocol.mos(), 'Daly 0x93');
    await Future.delayed(const Duration(milliseconds: 350));
    await _send(w, DalyProtocol.cells(), 'Daly 0x95');
    await Future.delayed(const Duration(milliseconds: 350));
    await _send(w, DalyProtocol.temps(), 'Daly 0x96');
  }

  Future<void> disconnect() async {
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
