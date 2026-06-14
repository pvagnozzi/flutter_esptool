// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('getFlashId uses SPI attach + register SPI command flow', () async {
    final transport = _ScriptedInfoTransport();
    final info = InfoService(transport: transport);

    final result = await info.getFlashId();

    expect(result.isSuccess, isTrue);
    final value = (result as Success<EspFlashInfo>).value;
    expect(value.manufacturerId, 0xEF);
    expect(value.deviceId, 0x40);
    expect(value.capacityId, 0x18);
    expect(value.manufacturerName, 'Winbond');
    expect(value.capacityBytes, 1 << 0x18);
    expect(transport.seenSpiAttach, isTrue);
    expect(transport.seenWriteReg, isTrue);
  });
}

class _ScriptedInfoTransport implements EspTransportInterface {
  static const int _chipMagicRegister = 0x40001000;
  static const int _esp32MacLowRegister = 0x6001A044;
  static const int _esp32MacHighRegister = 0x6001A048;
  static const int _spiBase = 0x3FF42000;
  static const int _spiCmdReg = _spiBase + 0x00;
  static const int _spiUsrReg = _spiBase + 0x1C;
  static const int _spiUsr2Reg = _spiBase + 0x24;
  static const int _spiW0Reg = _spiBase + 0x80;
  static const int _spiCmdUsr = 1 << 18;

  final Map<int, int> _registers = <int, int>{
    _chipMagicRegister: 0x00F01D83,
    _esp32MacLowRegister: 0x33445566,
    _esp32MacHighRegister: 0x00001122,
    _spiUsrReg: 0,
    _spiUsr2Reg: 0,
    _spiW0Reg: 0x001840EF,
  };

  bool seenSpiAttach = false;
  bool seenWriteReg = false;
  bool _open = true;
  int _cmdBusyReads = 0;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(EspConfig config) async {
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<EspResponse> sendCommand(
    EspCommand command, {
    Duration? timeout,
  }) async {
    switch (command.opcode) {
      case EspCommandOpcode.spiAttach:
        seenSpiAttach = true;
        return _ok(EspCommandOpcode.spiAttach);
      case EspCommandOpcode.readReg:
        final addr = ByteData.sublistView(command.data).getUint32(0, Endian.little);
        if (addr == _spiCmdReg) {
          _cmdBusyReads += 1;
          if (_cmdBusyReads == 1) {
            return _ok(EspCommandOpcode.readReg, value: _spiCmdUsr);
          }
          return _ok(EspCommandOpcode.readReg, value: 0);
        }
        return _ok(EspCommandOpcode.readReg, value: _registers[addr] ?? 0);
      case EspCommandOpcode.writeReg:
        seenWriteReg = true;
        final data = ByteData.sublistView(command.data);
        final addr = data.getUint32(0, Endian.little);
        final value = data.getUint32(4, Endian.little);
        _registers[addr] = value;
        if (addr == _spiCmdReg && value == _spiCmdUsr) {
          _cmdBusyReads = 0;
          _registers[_spiW0Reg] = 0x001840EF;
        }
        return _ok(EspCommandOpcode.writeReg);
      default:
        return _ok(command.opcode);
    }
  }

  static EspResponse _ok(
    EspCommandOpcode opcode, {
    int value = 0,
  }) {
    return EspResponse(
      opcode: opcode,
      value: value,
      data: Uint8List(0),
      status: 0,
      error: 0,
    );
  }
}
