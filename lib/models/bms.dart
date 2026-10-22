/// Parsed snapshot of the battery from the BMS.
class BmsData {
  final double? packVoltage; // V
  final double? current; // A, +charging / -discharging
  final int? soc; // %
  final double? remainingAh;
  final double? nominalAh;
  final int? cycles;
  final bool? chargeMos;
  final bool? dischargeMos;
  final List<double> temperatures; // °C
  final List<int> cellMillivolts; // mV per cell
  final int? protectionFlags;
  final DateTime updated;

  BmsData({
    this.packVoltage,
    this.current,
    this.soc,
    this.remainingAh,
    this.nominalAh,
    this.cycles,
    this.chargeMos,
    this.dischargeMos,
    this.temperatures = const [],
    this.cellMillivolts = const [],
    this.protectionFlags,
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  int? get cellCount => cellMillivolts.isEmpty ? null : cellMillivolts.length;
  int? get maxCellMv => cellMillivolts.isEmpty ? null : cellMillivolts.reduce((a, b) => a > b ? a : b);
  int? get minCellMv => cellMillivolts.isEmpty ? null : cellMillivolts.reduce((a, b) => a < b ? a : b);
  int? get spreadMv => (maxCellMv == null || minCellMv == null) ? null : maxCellMv! - minCellMv!;
  double? get power => (packVoltage == null || current == null) ? null : packVoltage! * current!;

  /// Merge a partial update (basic info and cell voltages arrive in separate
  /// frames) into a new snapshot.
  BmsData merge(BmsData other) => BmsData(
        packVoltage: other.packVoltage ?? packVoltage,
        current: other.current ?? current,
        soc: other.soc ?? soc,
        remainingAh: other.remainingAh ?? remainingAh,
        nominalAh: other.nominalAh ?? nominalAh,
        cycles: other.cycles ?? cycles,
        chargeMos: other.chargeMos ?? chargeMos,
        dischargeMos: other.dischargeMos ?? dischargeMos,
        temperatures: other.temperatures.isNotEmpty ? other.temperatures : temperatures,
        cellMillivolts: other.cellMillivolts.isNotEmpty ? other.cellMillivolts : cellMillivolts,
        protectionFlags: other.protectionFlags ?? protectionFlags,
        updated: DateTime.now(),
      );
}
