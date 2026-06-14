/// Snapshot of serial modem control and status lines.
///
/// [rts] and [dtr] are output control lines managed by the local device.
/// [cts], [dsr], and [dcd] are input/status lines reported by the peer or
/// adapter when the platform backend exposes them.
class SerialControlSignals {
  /// Creates a modem-control signal snapshot.
  const SerialControlSignals({
    this.mask = 0,
    this.rts = false,
    this.cts = false,
    this.dtr = false,
    this.dsr = false,
    this.dcd = false,
  });

  /// Platform-specific raw bit mask, when available.
  final int mask;

  /// Request To Send output state.
  final bool rts;

  /// Clear To Send input state.
  final bool cts;

  /// Data Terminal Ready output state.
  final bool dtr;

  /// Data Set Ready input state.
  final bool dsr;

  /// Data Carrier Detect input state.
  final bool dcd;

  /// Creates a copy with selected fields replaced.
  SerialControlSignals copyWith({
    int? mask,
    bool? rts,
    bool? cts,
    bool? dtr,
    bool? dsr,
    bool? dcd,
  }) {
    return SerialControlSignals(
      mask: mask ?? this.mask,
      rts: rts ?? this.rts,
      cts: cts ?? this.cts,
      dtr: dtr ?? this.dtr,
      dsr: dsr ?? this.dsr,
      dcd: dcd ?? this.dcd,
    );
  }

  /// Builds a signal snapshot from a platform map.
  factory SerialControlSignals.fromMap(Map<dynamic, dynamic> map) {
    return SerialControlSignals(
      mask: map['mask'] as int? ?? 0,
      rts: map['rts'] as bool? ?? false,
      cts: map['cts'] as bool? ?? false,
      dtr: map['dtr'] as bool? ?? false,
      dsr: map['dsr'] as bool? ?? false,
      dcd: map['dcd'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SerialControlSignals &&
          runtimeType == other.runtimeType &&
          mask == other.mask &&
          rts == other.rts &&
          cts == other.cts &&
          dtr == other.dtr &&
          dsr == other.dsr &&
          dcd == other.dcd;

  @override
  int get hashCode =>
      mask.hashCode ^
      rts.hashCode ^
      cts.hashCode ^
      dtr.hashCode ^
      dsr.hashCode ^
      dcd.hashCode;

  @override
  String toString() =>
      'SerialControlSignals(mask: $mask, rts: $rts, cts: $cts, '
      'dtr: $dtr, dsr: $dsr, dcd: $dcd)';
}
