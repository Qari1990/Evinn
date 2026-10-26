import 'dart:typed_data';
import '../models/bms.dart';

/// Classic Daly Smart BMS serial protocol over BLE (service FFF0 / write FFF2 /
/// notify FFF1). Fixed 13-byte frames.
///
/// Command:  A5 40 <cmd> 08 <8 data = 0> <checksum>
/// Response: A5 01 <cmd> 08 <8 data>     <checksum>   (0x95/0x96 are multi-frame)
///   checksum = sum(first 12 bytes) & 0xFF
class DalyProtocol {
  static Uint8List command(int cmd) {
    final b = <int>[0xA5, 0x40, cmd, 0x08, 0, 0, 0, 0, 0, 0, 0, 0];
    var sum = 0;
    for (final x in b) {
      sum += x;
    }
    b.add(sum & 0xFF);
    return Uint8List.fromList(b);
  }

  static Uint8List soc() => command(0x90); // pack V / current / SOC
  static Uint8List minMaxCell() => command(0x91); // max/min cell mV + numbers
  static Uint8List minMaxTemp() => command(0x92); // max/min temp + sensor nos
  static Uint8List mos() => command(0x93); // state, MOS, residual capacity
  static Uint8List status() => command(0x94); // cell / temp counts, charger/load
  static Uint8List cells() => command(0x95); // per-cell voltages (multi-frame)
  static Uint8List temps() => command(0x96); // per-sensor temperatures
  static Uint8List balance() => command(0x97); // cell balancing bitmask
  static Uint8List faults() => command(0x98); // protection / fault flags

  /// Every read command, in a sensible poll order.
  static List<(String, Uint8List)> get pollSet => [
        ('0x90 soc', soc()),
        ('0x91 cell hi/lo', minMaxCell()),
        ('0x92 temp hi/lo', minMaxTemp()),
        ('0x93 mos', mos()),
        ('0x94 status', status()),
        ('0x95 cells', cells()),
        ('0x96 temps', temps()),
        ('0x97 balance', balance()),
        ('0x98 faults', faults()),
      ];

  final List<int> _buf = [];
  final List<int> _cells = [];
  final List<double> _temps = [];

  void reset() {
    _buf.clear();
    _cells.clear();
    _temps.clear();
  }

  BmsData? addChunk(List<int> chunk) {
    _buf.addAll(chunk);
    BmsData? out;
    while (true) {
      final start = _buf.indexOf(0xA5);
      if (start < 0) {
        _buf.clear();
        break;
      }
      if (start > 0) _buf.removeRange(0, start);
      if (_buf.length < 13) break;
      final f = _buf.sublist(0, 13);
      _buf.removeRange(0, 13);
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        sum += f[i];
      }
      if ((sum & 0xFF) != f[12]) continue; // bad checksum, skip
      final parsed = _parse(f[2], f.sublist(4, 12));
      if (parsed != null) out = out == null ? parsed : out.merge(parsed);
    }
    return out;
  }

  BmsData? _parse(int cmd, List<int> d) {
    int u16(int o) => (d[o] << 8) | d[o + 1];
    int u32(int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];
    switch (cmd) {
      case 0x90:
        final cur = (u16(4) - 30000) / 10.0;
        return BmsData(
          packVoltage: u16(0) / 10.0,
          current: cur,
          soc: (u16(6) / 10.0).round(),
          state: cur > 0.3 ? 'charging' : (cur < -0.3 ? 'discharging' : 'idle'),
        );
      case 0x91:
        return BmsData(
          // keep cell numbers; mV themselves come from 0x95
          maxCellNo: d[2],
          minCellNo: d[5],
        );
      case 0x92:
        return BmsData(
          maxTempC: (d[0] - 40).toDouble(),
          minTempC: (d[2] - 40).toDouble(),
        );
      case 0x93:
        return BmsData(
          state: d[0] == 1 ? 'charging' : (d[0] == 2 ? 'discharging' : 'idle'),
          chargeMos: d[1] != 0,
          dischargeMos: d[2] != 0,
          remainingAh: u32(4) / 1000.0,
        );
      case 0x94:
        return BmsData(
          chargerConnected: d[2] != 0,
          loadConnected: d[3] != 0,
        );
      case 0x95:
        if (d[0] == 1) _cells.clear();
        for (var i = 0; i < 3; i++) {
          final mv = u16(1 + i * 2);
          if (mv > 0 && mv < 6000) _cells.add(mv);
        }
        return BmsData(cellMillivolts: List<int>.from(_cells));
      case 0x96:
        if (d[0] == 1) _temps.clear();
        for (var i = 1; i < 8; i++) {
          final raw = d[i];
          if (raw != 0 && raw != 0xFF) _temps.add((raw - 40).toDouble());
        }
        return BmsData(temperatures: List<double>.from(_temps));
      case 0x97:
        final balancing = <int>[];
        for (var byte = 0; byte < 6; byte++) {
          for (var bit = 0; bit < 8; bit++) {
            if ((d[byte] & (1 << bit)) != 0) balancing.add(byte * 8 + bit + 1);
          }
        }
        return BmsData(balancingCells: balancing);
      case 0x98:
        return BmsData(alarms: _faults(d));
      default:
        return null;
    }
  }

  // Decode the common Daly 0x98 protection/fault bits into readable names.
  static List<String> _faults(List<int> d) {
    final a = <String>[];
    void chk(int byte, int bit, String name) {
      if (byte < d.length && (d[byte] & (1 << bit)) != 0) a.add(name);
    }
    chk(0, 0, 'Cell voltage high');
    chk(0, 2, 'Cell voltage low');
    chk(0, 4, 'Pack voltage high');
    chk(0, 6, 'Pack voltage low');
    chk(1, 0, 'Charge temp high');
    chk(1, 2, 'Charge temp low');
    chk(1, 4, 'Discharge temp high');
    chk(1, 6, 'Discharge temp low');
    chk(2, 0, 'Charge overcurrent');
    chk(2, 2, 'Discharge overcurrent');
    chk(2, 4, 'SOC high');
    chk(2, 6, 'SOC low');
    chk(3, 0, 'Cell voltage difference');
    chk(3, 2, 'Temperature difference');
    chk(4, 0, 'Charge MOSFET temp high');
    chk(4, 1, 'Discharge MOSFET temp high');
    chk(4, 2, 'Charge MOSFET temp sensor fault');
    chk(5, 0, 'Cell count mismatch');
    chk(5, 1, 'NTC sensor fault');
    chk(6, 0, 'Charge MOSFET fault');
    chk(6, 1, 'Discharge MOSFET fault');
    return a;
  }
}
