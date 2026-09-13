// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';

/// Builds a successful [EspResponse] with the given [value] and optional [data].
EspResponse okResponse(
  EspCommandOpcode opcode, {
  int value = 0,
  Uint8List? data,
}) =>
    EspResponse(
      opcode: opcode,
      value: value,
      data: data ?? Uint8List(0),
      status: 0,
      error: 0,
    );

/// Builds a failing [EspResponse] (status != 0).
EspResponse failResponse(
  EspCommandOpcode opcode, {
  int status = 1,
  int error = 5,
}) =>
    EspResponse(
      opcode: opcode,
      value: 0,
      data: Uint8List(0),
      status: status,
      error: error,
    );

/// A programmable fake [EspTransportInterface] for unit tests.
///
/// * [onCommand] — if set, fully controls the response for every command.
/// * [readRegValues] — a queue of values returned for consecutive READ_REG
///   commands (falls back to [defaultReadValue] when exhausted).
/// * [failOpcodes] — opcodes that should return a failing response.
/// * [throwOnOpcodes] — opcodes that should throw an [EspError].
class FakeTransport implements EspTransportInterface {
  FakeTransport({
    this.onCommand,
    List<int>? readRegValues,
    this.defaultReadValue = 0,
    Set<EspCommandOpcode>? failOpcodes,
    Set<EspCommandOpcode>? throwOnOpcodes,
    this.securityInfoData,
    List<int>? readRawBytes,
  })  : _readRegValues = List<int>.of(readRegValues ?? const <int>[]),
        _readRawBytes = List<int>.of(readRawBytes ?? const <int>[]),
        failOpcodes = failOpcodes ?? const <EspCommandOpcode>{},
        throwOnOpcodes = throwOnOpcodes ?? const <EspCommandOpcode>{};

  final EspResponse Function(EspCommand command)? onCommand;
  final List<int> _readRegValues;
  final int defaultReadValue;
  final Set<EspCommandOpcode> failOpcodes;
  final Set<EspCommandOpcode> throwOnOpcodes;
  final Uint8List? securityInfoData;
  final List<int> _readRawBytes;

  /// Every command that was sent, in order.
  final List<EspCommand> sentCommands = <EspCommand>[];
  int _readIndex = 0;
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(EspConfig config) async => _open = true;

  @override
  Future<void> close() async => _open = false;

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<void> hardReset() async {}

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<List<int>> readRaw(int count, {Duration? timeout}) async {
    if (_readRawBytes.isEmpty) return <int>[];
    final n = count < _readRawBytes.length ? count : _readRawBytes.length;
    final out = _readRawBytes.sublist(0, n);
    _readRawBytes.removeRange(0, n);
    return out;
  }

  @override
  Future<void> flushRx() async {}

  @override
  Future<void> writeRaw(List<int> bytes, {Duration? timeout}) async {}

  @override
  Future<void> reopenPort({
    Duration waitBefore = const Duration(milliseconds: 1500),
  }) async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) async {
    sentCommands.add(command);

    if (throwOnOpcodes.contains(command.opcode)) {
      throw EspError(
        type: EspErrorType.timeout,
        message: 'forced throw for ${command.opcode}',
      );
    }
    if (onCommand != null) {
      return onCommand!(command);
    }
    if (failOpcodes.contains(command.opcode)) {
      return failResponse(command.opcode);
    }

    switch (command.opcode) {
      case EspCommandOpcode.readReg:
        final value = _readIndex < _readRegValues.length
            ? _readRegValues[_readIndex]
            : defaultReadValue;
        _readIndex++;
        return okResponse(command.opcode, value: value);
      case EspCommandOpcode.getSecurityInfo:
        return okResponse(command.opcode, data: securityInfoData);
      default:
        return okResponse(command.opcode);
    }
  }
}
