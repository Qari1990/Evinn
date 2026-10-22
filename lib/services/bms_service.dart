import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/bms.dart';
import 'jbd_protocol.dart';

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

  Stream<BmsStatus> get status => _statusCtrl.stream;
  Stream<BmsData> get data => _dataCtrl.stream;
  Stream<String> get errors => _errorCtrl.stream;

  final _jbd = JbdProtocol();
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
    try {
      if (!await _ensurePermissions()) {
        _errorCtrl.add('Bluetooth/Location permission denied');
        _statusCtrl.add(BmsStatus.error);
        return;
      }
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        _errorCtrl.add('Please turn on Bluetooth');
        _statusCtrl.add(BmsStatus.error);
        return;
      }

      _statusCtrl.add(BmsStatus.scanning);
      final completer = Completer<BluetoothDevice>();
      await _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final matchId = remoteId != null && r.device.remoteId.str.toUpperCase() == remoteId.toUpperCase();
          final matchSvc = r.advertisementData.serviceUuids.map((g) => g.str.toLowerCase()).contains(serviceFff0.str.toLowerCase());
          if (matchId || matchSvc) {
            if (!completer.isCompleted) completer.complete(r.device);
          }
        }
      });
      await FlutterBluePlus.startScan(
        withServices: [serviceFff0],
        timeout: const Duration(seconds: 15),
      );

      final device = await completer.future.timeout(
        const Duration(seconds: 16),
        onTimeout: () => throw Exception('BMS not found — is the bike in range and the Daly app closed?'),
      );
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();

      _statusCtrl.add(BmsStatus.connecting);
      _device = device;
      await device.connect(timeout: const Duration(seconds: 15));

      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase().endsWith('fff0'),
        orElse: () => throw Exception('BMS service FFF0 not found'),
      );
      final notify = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().endsWith('fff1'));
      _write = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase().endsWith('fff2'));

      await notify.setNotifyValue(true);
      _jbd.reset();
      _notifySub = notify.onValueReceived.listen((chunk) {
        final parsed = _jbd.addChunk(chunk);
        if (parsed != null) {
          _snapshot = _snapshot.merge(parsed);
          _dataCtrl.add(_snapshot);
        }
      });

      _statusCtrl.add(BmsStatus.connected);
      await _poll();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      _errorCtrl.add(e.toString());
      _statusCtrl.add(BmsStatus.error);
      await disconnect();
    }
  }

  Future<void> _poll() async {
    final w = _write;
    if (w == null) return;
    final withoutResp = w.properties.writeWithoutResponse;
    await w.write(JbdProtocol.readBasicInfo(), withoutResponse: withoutResp);
    await Future.delayed(const Duration(milliseconds: 500));
    await w.write(JbdProtocol.readCellVolts(), withoutResponse: withoutResp);
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    await _notifySub?.cancel();
    await _scanSub?.cancel();
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
  }
}
