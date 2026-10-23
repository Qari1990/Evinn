import 'dart:typed_data';
import '../models/bms.dart';

/// Classic Daly Smart BMS serial protocol (over BLE service FFF0 / write FFF2 /
/// notify FFF1). Different from JBD: fixed 13-byte frames.
///
/// Command:  A5 40 <cmd> 08 <8 data bytes = 0> <checksum>
/// Response: A5 01 <cmd> 08 <8 data bytes>      <checksum>
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
  static Uint8List mos() => command(0x93); // charge/discharge MOS state
  static Uint8List cells() => command(0x95); // per-cell voltages (multi-frame)
  static Uint8List temps() => command(0x96); // per-cell temperatures
  static Uint8List status() => command(0x94); // cell / temp sensor counts

  final List<int> _buf = [];
  final List<int> _cells = [];

  void reset() {
    _buf.clear();
    _cells.clear();
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
    switch (cmd) {
      case 0x90:
        return BmsData(
          packVoltage: u16(0) / 10.0,
          current: (u16(4) - 30000) / 10.0, // offset-encoded, +charge/-discharge
          soc: (u16(6) / 10.0).round(),
        );
      case 0x93:
        return BmsData(chargeMos: d[1] != 0, dischargeMos: d[2] != 0);
      case 0x95:
        // d[0] = frame number (1..), then 3 cells * mV.
        if (d[0] == 1) _cells.clear();
        for (var i = 0; i < 3; i++) {
          final mv = u16(1 + i * 2);
          if (mv > 0 && mv < 6000) _cells.add(mv);
        }
        return BmsData(cellMillivolts: List<int>.from(_cells));
      case 0x96:
        // d[0] = frame number, d[1] = temperature + 40 offset (°C).
        return BmsData(temperatures: [(d[1] - 40).toDouble()]);
      default:
        return null;
    }
  }
}
