// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/transport/esp_transport.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform_serial/platform_serial.dart';

class MockSerialPortInterface extends Mock implements SerialPortInterface {}

void main() {
  late MockSerialPortInterface serial;
  late EspTransport transport;

  setUpAll(() {
    registerFallbackValue(
      const SerialConfig(
        portName: 'COM1',
        baudRate: 115200,
      ),
    );
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const Duration(seconds: 1));
  });

  setUp(() {
    serial = MockSerialPortInterface();
    transport = EspTransport(serial: serial);
    when(() => serial.isOpen).thenReturn(true);
    when(() => serial.open(any())).thenAnswer((_) async {});
    when(() => serial.resetBuffers()).thenAnswer((_) async {});
    when(() => serial.close()).thenAnswer((_) async {});
    when(() => serial.flush()).thenAnswer((_) async {});
    when(() => serial.write(any(), timeout: any(named: 'timeout')))
        .thenAnswer((_) async => 1);
  });

  group('EspTransport', () {
    test('open calls serial.open with the expected config', () async {
      const config = EspConfig(portName: 'COM5', initialBaudRate: 74880);

      await transport.open(config);

      final captured = verify(() => serial.open(captureAny())).captured.single
          as SerialConfig;
      expect(captured.portName, 'COM5');
      expect(captured.baudRate, 74880);
    });

    test('sendCommand writes a SLIP-encoded command packet', () async {
      await transport.open(const EspConfig(portName: 'COM5'));
      when(() => serial.read(any(), timeout: any(named: 'timeout'))).thenAnswer(
        (_) async => _buildSlipResponse(EspCommandOpcode.sync),
      );

      final command = EspCommand(
        opcode: EspCommandOpcode.sync,
        data: Uint8List.fromList(<int>[0x01, 0x02]),
        checksum: 0,
      );
      await transport.sendCommand(command);

      final written = verify(
        () => serial.write(captureAny(), timeout: any(named: 'timeout')),
      ).captured.first as Uint8List;
      final packet = Uint8List.fromList(<int>[
        0x00,
        EspCommandOpcode.sync.value,
        0x02,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x01,
        0x02,
      ]);
      expect(written, SlipCodec.encode(packet));
    });

    test('sendCommand decodes and parses a response', () async {
      await transport.open(const EspConfig(portName: 'COM5'));
      when(() => serial.read(any(), timeout: any(named: 'timeout'))).thenAnswer(
        (_) async => _buildSlipResponse(
          EspCommandOpcode.readReg,
          value: 0x12345678,
          data: Uint8List.fromList(<int>[0xAA, 0xBB]),
        ),
      );

      final response = await transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.readReg, data: Uint8List(4)),
      );

      expect(response.opcode, EspCommandOpcode.readReg);
      expect(response.value, 0x12345678);
      expect(response.data, <int>[0xAA, 0xBB]);
      expect(response.isSuccess, isTrue);
    });

    test('sendCommand throws timeout when reads never complete', () async {
      await transport.open(
        const EspConfig(portName: 'COM5', timeout: Duration(milliseconds: 30)),
      );
      when(() => serial.read(any(), timeout: any(named: 'timeout'))).thenAnswer(
        (_) => Future<Uint8List>.delayed(
          const Duration(milliseconds: 100),
          () => Uint8List(0),
        ),
      );

      expect(
        () => transport.sendCommand(
          EspCommand(opcode: EspCommandOpcode.sync),
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(
          isA<EspError>().having(
            (error) => error.type,
            'type',
            EspErrorType.timeout,
          ),
        ),
      );
    });

    test('sendCommand accumulates partial packets across reads', () async {
      await transport.open(const EspConfig(portName: 'COM5'));
      final frame = _buildSlipResponse(EspCommandOpcode.sync, value: 0x55AA);
      var call = 0;
      when(() => serial.read(any(), timeout: any(named: 'timeout')))
          .thenAnswer((_) async {
        call += 1;
        if (call == 1) {
          return Uint8List.fromList(frame.sublist(0, 3));
        }
        return Uint8List.fromList(frame.sublist(3));
      });

      final response = await transport
          .sendCommand(EspCommand(opcode: EspCommandOpcode.sync));
      expect(response.value, 0x55AA);
    });

    test('changeBaud sends the expected command', () async {
      await transport.open(const EspConfig(portName: 'COM5'));
      when(() => serial.read(any(), timeout: any(named: 'timeout'))).thenAnswer(
        (_) async => _buildSlipResponse(EspCommandOpcode.changeBaud),
      );

      await transport.changeBaud(921600);

      final writes = verify(
        () => serial.write(captureAny(), timeout: any(named: 'timeout')),
      ).captured;
      final decoded = SlipCodec.decode(writes.last as Uint8List);
      expect(decoded, isNotNull);
      final data = ByteData.sublistView(decoded!);
      expect(data.getUint8(1), EspCommandOpcode.changeBaud.value);
      expect(data.getUint32(8, Endian.little), 921600);
    });
  });
}

Uint8List _buildSlipResponse(
  EspCommandOpcode opcode, {
  int value = 0,
  Uint8List? data,
  int status = 0,
  int error = 0,
}) {
  final payload =
      Uint8List.fromList(<int>[...(data ?? Uint8List(0)), status, error]);
  final bytes = Uint8List(8 + payload.length);
  final byteData = ByteData.sublistView(bytes);
  byteData.setUint8(0, 0x01);
  byteData.setUint8(1, opcode.value);
  byteData.setUint16(2, payload.length, Endian.little);
  byteData.setUint32(4, value, Endian.little);
  bytes.setRange(8, bytes.length, payload);
  return SlipCodec.encode(bytes);
}
