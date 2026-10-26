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
  final List<double> temperatures; // °C (per sensor)
  final List<int> cellMillivolts; // mV per cell
  final int? protectionFlags;

  // Extended (full Daly command set).
  final int? maxCellNo; // 1-based
  final int? minCellNo;
  final double? maxTempC;
  final double? minTempC;
  final List<int> balancingCells; // 1-based cell numbers currently balancing
  final List<String> alarms; // active protection/fault names
  final bool? chargerConnected;
  final bool? loadConnected;
  final String? state; // 'charging' | 'discharging' | 'idle'

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
    this.maxCellNo,
    this.minCellNo,
    this.maxTempC,
    this.minTempC,
    this.balancingCells = const [],
    this.alarms = const [],
    this.chargerConnected,
    this.loadConnected,
    this.state,
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  int? get cellCount => cellMillivolts.isEmpty ? null : cellMillivolts.length;
  int? get maxCellMv => cellMillivolts.isEmpty ? null : cellMillivolts.reduce((a, b) => a > b ? a : b);
  int? get minCellMv => cellMillivolts.isEmpty ? null : cellMillivolts.reduce((a, b) => a < b ? a : b);
  int? get spreadMv => (maxCellMv == null || minCellMv == null) ? null : maxCellMv! - minCellMv!;
  double? get avgCellMv => cellMillivolts.isEmpty
      ? null
      : cellMillivolts.reduce((a, b) => a + b) / cellMillivolts.length;
  double? get power => (packVoltage == null || current == null) ? null : packVoltage! * current!;
  bool get hasAnyData => packVoltage != null || cellMillivolts.isNotEmpty || soc != null;

  /// Remaining energy in watt-hours (remaining Ah × pack voltage). Used for the
  /// range estimate.
  double? get remainingWh =>
      (remainingAh == null || packVoltage == null) ? null : remainingAh! * packVoltage!;

  /// Full-pack capacity inferred from the current reading (remainingAh at this
  /// SOC). Null unless we have both and SOC is meaningful.
  double? get inferredFullAh => (remainingAh == null || soc == null || soc! < 5)
      ? null
      : remainingAh! / (soc! / 100.0);

  /// Chemistry inferred from resting per-cell voltage. LiFePO4 cells sit near
  /// 3.2–3.4 V; Li-ion (NMC) ranges higher. Rough — labelled "est." in the UI.
  String? get chemistry {
    final mv = avgCellMv;
    if (mv == null) return null;
    if (mv >= 2500 && mv <= 3450) return 'LFP';
    if (mv > 3450 && mv <= 4250) return 'Li-ion';
    return null;
  }

  /// Merge a partial update (each command's reply arrives separately) into a
  /// new snapshot, keeping previously-known fields.
  BmsData merge(BmsData o) => BmsData(
        packVoltage: o.packVoltage ?? packVoltage,
        current: o.current ?? current,
        soc: o.soc ?? soc,
        remainingAh: o.remainingAh ?? remainingAh,
        nominalAh: o.nominalAh ?? nominalAh,
        cycles: o.cycles ?? cycles,
        chargeMos: o.chargeMos ?? chargeMos,
        dischargeMos: o.dischargeMos ?? dischargeMos,
        temperatures: o.temperatures.isNotEmpty ? o.temperatures : temperatures,
        cellMillivolts: o.cellMillivolts.isNotEmpty ? o.cellMillivolts : cellMillivolts,
        protectionFlags: o.protectionFlags ?? protectionFlags,
        maxCellNo: o.maxCellNo ?? maxCellNo,
        minCellNo: o.minCellNo ?? minCellNo,
        maxTempC: o.maxTempC ?? maxTempC,
        minTempC: o.minTempC ?? minTempC,
        balancingCells: o.balancingCells.isNotEmpty ? o.balancingCells : balancingCells,
        alarms: o.alarms.isNotEmpty ? o.alarms : alarms,
        chargerConnected: o.chargerConnected ?? chargerConnected,
        loadConnected: o.loadConnected ?? loadConnected,
        state: o.state ?? state,
        updated: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'packVoltage': packVoltage,
        'current': current,
        'soc': soc,
        'remainingAh': remainingAh,
        'nominalAh': nominalAh,
        'cycles': cycles,
        'chargeMos': chargeMos,
        'dischargeMos': dischargeMos,
        'temperatures': temperatures,
        'cellMillivolts': cellMillivolts,
        'protectionFlags': protectionFlags,
        'maxCellNo': maxCellNo,
        'minCellNo': minCellNo,
        'maxTempC': maxTempC,
        'minTempC': minTempC,
        'balancingCells': balancingCells,
        'alarms': alarms,
        'chargerConnected': chargerConnected,
        'loadConnected': loadConnected,
        'state': state,
        'updated': updated.toIso8601String(),
      };

  factory BmsData.fromJson(Map<String, dynamic> j) {
    List<double> dl(dynamic v) => (v as List?)?.map((e) => (e as num).toDouble()).toList() ?? const [];
    List<int> il(dynamic v) => (v as List?)?.map((e) => (e as num).toInt()).toList() ?? const [];
    return BmsData(
      packVoltage: (j['packVoltage'] as num?)?.toDouble(),
      current: (j['current'] as num?)?.toDouble(),
      soc: (j['soc'] as num?)?.toInt(),
      remainingAh: (j['remainingAh'] as num?)?.toDouble(),
      nominalAh: (j['nominalAh'] as num?)?.toDouble(),
      cycles: (j['cycles'] as num?)?.toInt(),
      chargeMos: j['chargeMos'] as bool?,
      dischargeMos: j['dischargeMos'] as bool?,
      temperatures: dl(j['temperatures']),
      cellMillivolts: il(j['cellMillivolts']),
      protectionFlags: (j['protectionFlags'] as num?)?.toInt(),
      maxCellNo: (j['maxCellNo'] as num?)?.toInt(),
      minCellNo: (j['minCellNo'] as num?)?.toInt(),
      maxTempC: (j['maxTempC'] as num?)?.toDouble(),
      minTempC: (j['minTempC'] as num?)?.toDouble(),
      balancingCells: il(j['balancingCells']),
      alarms: (j['alarms'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      chargerConnected: j['chargerConnected'] as bool?,
      loadConnected: j['loadConnected'] as bool?,
      state: j['state'] as String?,
      updated: DateTime.tryParse(j['updated']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
