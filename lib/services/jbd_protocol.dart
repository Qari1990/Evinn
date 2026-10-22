import 'dart:typed_data';
import '../models/bms.dart';

/// JBD / JiaBaiDa BMS serial protocol (the one used by the "Daly higher-grade"
/// boards, incl. WAQAR's JHB-R24TH, over BLE service FFF0 / write FFF2 / notify
/// FFF1). Also known as the Xiaoxiang protocol.
///
/// Read frame:  DD A5 <reg> 00 FF <chk_hi> <chk_lo> 77
///   checksum = 0x10000 - (reg + len)   (len = 0 for reads)
/// Response:    DD <reg> <status> <len> <data...> <chk_hi> <chk_lo> 77
class JbdProtocol {
  static const int regBasicInfo = 0x03; // pack V/I, SOC, temps, MOS, cycles...
  static const int regCellVolts = 0x04; // per-cell voltages
  static const int regHardware = 0x05; // name string

  /// Build a read command for [reg].
  static Uint8List readCommand(int reg) {
    final sum = (reg + 0x00) & 0xFFFF;
    final chk = (0x10000 - sum) & 0xFFFF;
    return Uint8List.fromList([0xDD, 0xA5, reg, 0x00, (chk >> 8) & 0xFF, chk & 0xFF, 0x77]);
  }

  static Uint8List readBasicInfo() => readCommand(regBasicInfo);
  static Uint8List readCellVolts() => readCommand(regCellVolts);

  /// Accumulates incoming notify chunks and emits a parsed [BmsData] when a
  /// complete, valid frame is assembled.
  final List<int> _buf = [];

  BmsData? addChunk(List<int> chunk) {
    _buf.addAll(chunk);
    return _tryParse();
  }

  void reset() => _buf.clear();

  BmsData? _tryParse() {
    // Find frame start.
    final start = _buf.indexOf(0xDD);
    if (start < 0) {
      _buf.clear();
      return null;
    }
    if (start > 0) _buf.removeRange(0, start);
    if (_buf.length < 4) return null;

    final reg = _buf[1];
    final status = _buf[2];
    final len = _buf[3];
    final frameLen = 4 + len + 3; // header(4) + data(len) + checksum(2) + end(1)
    if (_buf.length < frameLen) return null;

    final frame = _buf.sublist(0, frameLen);
    _buf.removeRange(0, frameLen);

    if (frame.last != 0x77) return null; // malformed; drop
    if (status != 0x00) return null; // BMS reported an error for this register

    final data = frame.sublist(4, 4 + len);
    switch (reg) {
      case regBasicInfo:
        return _parseBasic(data);
      case regCellVolts:
        return _parseCells(data);
      default:
        return null;
    }
  }

  static int _u16(List<int> d, int o) => (d[o] << 8) | d[o + 1];
  static int _i16(List<int> d, int o) {
    final v = _u16(d, o);
    return v > 0x7FFF ? v - 0x10000 : v;
  }

  BmsData _parseBasic(List<int> d) {
    if (d.length < 23) return BmsData();
    final volt = _u16(d, 0) / 100.0; // 10 mV units
    final curr = _i16(d, 2) / 100.0; // 10 mA units, signed
    final resid = _u16(d, 4) * 10; // mAh
    final nominal = _u16(d, 6) * 10; // mAh
    final cycles = _u16(d, 8);
    final prot = _u16(d, 16);
    final soc = d[19];
    final fet = d[20]; // bit0 charge, bit1 discharge
    final ntc = d[22];
    final temps = <double>[];
    for (var i = 0; i < ntc; i++) {
      final off = 23 + i * 2;
      if (off + 1 < d.length) {
        temps.add(((_u16(d, off) - 2731) / 10.0)); // 0.1 K -> °C
      }
    }
    return BmsData(
      packVoltage: volt,
      current: curr,
      soc: soc,
      remainingAh: resid / 1000.0,
      nominalAh: nominal / 1000.0,
      cycles: cycles,
      chargeMos: (fet & 0x01) != 0,
      dischargeMos: (fet & 0x02) != 0,
      temperatures: temps,
      protectionFlags: prot,
    );
  }

  BmsData _parseCells(List<int> d) {
    final n = d.length ~/ 2;
    final mv = <int>[];
    for (var i = 0; i < n; i++) {
      mv.add(_u16(d, i * 2));
    }
    return BmsData(cellMillivolts: mv);
  }
}
