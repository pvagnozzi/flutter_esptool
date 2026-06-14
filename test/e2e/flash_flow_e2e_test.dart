// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('flash flow e2e', () {
    test('good path connect detect writeFlash succeeds', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.sync: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.sync)),
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00F01D83))
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00001122))
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x33445566)),
          EspCommandOpcode.flashBegin: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashBegin)),
          EspCommandOpcode.flashData: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashData)),
          EspCommandOpcode.flashEnd: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashEnd)),
        },
      );
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);
      final flash = FlashService(transport: transport);

      final connectResult =
          await connection.connect(const EspConfig(portName: 'COM22'));
      final detectResult = await detection.detect();
      final flashResult = await flash.writeFlash(
        FlashParameters(
          offset: 0x1000,
          data: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      );

      expect(connectResult.isSuccess, isTrue);
      expect(detectResult.isSuccess, isTrue);
      expect(flashResult.isSuccess, isTrue);
    });

    test('sync failure exhausts retries', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.sync: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.sync, status: 1))
            ..add((_) => _successResponse(EspCommandOpcode.sync, status: 1)),
        },
      );
      final connection = ConnectionService(transport);
      final result = await connection.connect(
        const EspConfig(portName: 'COM22', syncRetries: 2),
      );

      expect(result.isFailure, isTrue);
      expect((result as Failure<void>).error.type, EspErrorType.syncFailed);
    });

    test('port unavailable maps serial errors', () async {
      final transport = ScriptedTransport(
        openError: SerialError(
          type: SerialErrorType.portNotFound,
          message: 'missing',
        ),
      );
      final connection = ConnectionService(transport);
      final result =
          await connection.connect(const EspConfig(portName: 'COM22'));

      expect(result.isFailure, isTrue);
      expect(
          (result as Failure<void>).error.type, EspErrorType.portUnavailable);
    });

    test('bad baud returns an EspError', () async {
      final transport = ScriptedTransport(
        changeBaudError:
            const EspError(type: EspErrorType.badBaudRate, message: 'nope'),
      );
      expect(
        () => transport.changeBaud(921600),
        throwsA(
          isA<EspError>()
              .having((error) => error.type, 'type', EspErrorType.badBaudRate),
        ),
      );
    });

    test('invalid chip returns invalidChip', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.sync: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.sync)),
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x12345678)),
        },
      );
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      await connection.connect(const EspConfig(portName: 'COM7'));
      final result = await detection.detect();
      expect(result.isFailure, isTrue);
      expect((result as Failure<EspChipInfo>).error.type,
          EspErrorType.invalidChip);
    });

    test('flash verify mismatch returns flashVerifyFailed', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.flashBegin: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashBegin)),
          EspCommandOpcode.flashData: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashData)),
          EspCommandOpcode.flashEnd: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashEnd)),
          EspCommandOpcode.flashMd5: Queue<EspResponse Function(EspCommand)>()
            ..add(
              (_) => _successResponse(
                EspCommandOpcode.flashMd5,
                data: Uint8List.fromList(
                  'deadbeefdeadbeefdeadbeefdeadbeef'.codeUnits,
                ),
              ),
            ),
        },
      );
      final flash = FlashService(transport: transport);
      final result = await flash.writeFlash(
        FlashParameters(
          offset: 0,
          data: Uint8List.fromList(<int>[1, 2, 3, 4]),
          verify: true,
        ),
      );

      expect(result.isFailure, isTrue);
      expect(
          (result as Failure<void>).error.type, EspErrorType.flashVerifyFailed);
    });

    test('partial packet accumulation works across split reads', () async {
      final fullFrame = _buildSlipResponse(EspCommandOpcode.sync);
      final serial = SplitResponseSerialPort(
        responses: <Uint8List>[
          Uint8List.fromList(fullFrame.sublist(0, 2)),
          Uint8List.fromList(fullFrame.sublist(2)),
        ],
      );
      final transport = EspTransport(serial: serial);
      await transport.open(const EspConfig(portName: 'COM8'));

      final response = await transport
          .sendCommand(EspCommand(opcode: EspCommandOpcode.sync));
      expect(response.isSuccess, isTrue);
    });

    test('eraseFlash without stub loaded succeeds when device responds',
        () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.flashBegin: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashBegin)),
          EspCommandOpcode.flashEnd: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashEnd)),
        },
      );
      final flash = FlashService(transport: transport);
      final result = await flash.eraseFlash();

      expect(result.isSuccess, isTrue);
    });

    test('flashBegin payload uses erase-size rounded to block size', () async {
      late EspCommand flashBeginCommand;
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.flashBegin: Queue<EspResponse Function(EspCommand)>()
            ..add((command) {
              flashBeginCommand = command;
              return _successResponse(EspCommandOpcode.flashBegin);
            }),
          EspCommandOpcode.flashData: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashData))
            ..add((_) => _successResponse(EspCommandOpcode.flashData)),
          EspCommandOpcode.flashEnd: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashEnd)),
        },
      );
      final flash = FlashService(transport: transport, blockSize: 8);

      final result = await flash.writeFlash(
        FlashParameters(
          offset: 0x1000,
          data: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
        ),
      );

      expect(result.isSuccess, isTrue);
      final payload = ByteData.sublistView(flashBeginCommand.data);
      expect(payload.getUint32(0, Endian.little), 16);
      expect(payload.getUint32(4, Endian.little), 2);
      expect(payload.getUint32(8, Endian.little), 8);
      expect(payload.getUint32(12, Endian.little), 0x1000);
    });

    test('writeFlash pads final block to the announced block size', () async {
      final flashDataCommands = <EspCommand>[];
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.flashBegin: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashBegin)),
          EspCommandOpcode.flashData: Queue<EspResponse Function(EspCommand)>()
            ..add((command) {
              flashDataCommands.add(command);
              return _successResponse(EspCommandOpcode.flashData);
            })
            ..add((command) {
              flashDataCommands.add(command);
              return _successResponse(EspCommandOpcode.flashData);
            }),
          EspCommandOpcode.flashEnd: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.flashEnd)),
        },
      );
      final flash = FlashService(transport: transport, blockSize: 8);

      final result = await flash.writeFlash(
        FlashParameters(
          offset: 0x1000,
          data: Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(flashDataCommands, hasLength(2));

      final firstBlock = flashDataCommands[0].data.sublist(16);
      final secondBlock = flashDataCommands[1].data.sublist(16);

      expect(firstBlock, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(secondBlock, <int>[9, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]);
    });
  });

  group('chip detection e2e', () {
    test('detect ESP32 chip family and magic value', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            // Magic register read (0x40001000) - ESP32 magic
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00F01D83))
            // EFUSE word 2 provides the upper two MAC bytes for ESP32
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00001122))
            // EFUSE word 1 provides the lower four MAC bytes for ESP32
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x33445566)),
        },
      );
      final detection = ChipDetectionService(transport);

      final result = await detection.detect();

      expect(result.isSuccess, isTrue);
      final chipInfo = (result as Success<EspChipInfo>).value;
      expect(chipInfo.family, ChipFamily.esp32);
      expect(chipInfo.magicValue, 0x00F01D83);
      expect(chipInfo.description, contains('ESP32'));
    });

    test('detect ESP32-S3 chip family by magic value', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            // ESP32-S3 magic value: 0x00000009
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00000009))
            // MAC low
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x11223344))
            // MAC high
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x0000AABB)),
        },
      );
      final detection = ChipDetectionService(transport);

      final result = await detection.detect();

      expect(result.isSuccess, isTrue);
      final chipInfo = (result as Success<EspChipInfo>).value;
      expect(chipInfo.family, ChipFamily.esp32s3);
      expect(chipInfo.magicValue, 0x00000009);
    });

    test('MAC address is correctly formatted from register values', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x00F01D83))
            // EFUSE word 2: top two MAC bytes after CRC trimming
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x0000EEFF))
            // EFUSE word 1: lower four MAC bytes
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0xAABBCCDD)),
        },
      );
      final detection = ChipDetectionService(transport);

      final result = await detection.detect();

      expect(result.isSuccess, isTrue);
      final chipInfo = (result as Success<EspChipInfo>).value;
      // Expected format on ESP32 uses EFUSE words 2 and 1 packed big-endian,
      // then trims the leading 2-byte CRC region.
      // = [0xEE, 0xFF, 0xAA, 0xBB, 0xCC, 0xDD] = ee:ff:aa:bb:cc:dd
      expect(chipInfo.macAddress, 'ee:ff:aa:bb:cc:dd');
    });

    test('detect ESP8266 uses correct MAC register addresses', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            // ESP8266 magic: 0xFFF0C101
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0xFFF0C101))
            // ESP8266 MAC low at 0x3FF00050
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x11223344))
            // ESP8266 MAC high at 0x3FF00054
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x0000AABB)),
        },
      );
      final detection = ChipDetectionService(transport);

      final result = await detection.detect();

      expect(result.isSuccess, isTrue);
      final chipInfo = (result as Success<EspChipInfo>).value;
      expect(chipInfo.family, ChipFamily.esp8266);
    });

    test('unknown chip magic returns invalidChip error', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0xDEADBEEF)),
        },
      );
      final detection = ChipDetectionService(transport);

      final result = await detection.detect();

      expect(result.isFailure, isTrue);
      expect(
        (result as Failure<EspChipInfo>).error.type,
        EspErrorType.invalidChip,
      );
    });

    test('chip detection flow success: magic -> family -> mac', () async {
      final transport = ScriptedTransport(
        handlers: <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{
          EspCommandOpcode.sync: Queue<EspResponse Function(EspCommand)>()
            ..add((_) => _successResponse(EspCommandOpcode.sync)),
          EspCommandOpcode.readReg: Queue<EspResponse Function(EspCommand)>()
            // Step 1: Read magic (0x40001000) - ESP32-S2
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x000007C6))
            // Step 2: Read MAC low (0x60001A044)
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x12345678))
            // Step 3: Read MAC high (0x60001A048)
            ..add((_) =>
                _successResponse(EspCommandOpcode.readReg, value: 0x0000ABCD)),
        },
      );
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      // Set up for potential sync
      final connectResult =
          await connection.connect(const EspConfig(portName: 'COM7'));
      final detectResult = await detection.detect();

      expect(connectResult.isSuccess, isTrue);
      expect(detectResult.isSuccess, isTrue);
      final chip = (detectResult as Success<EspChipInfo>).value;
      expect(chip.family, ChipFamily.esp32s2);
      expect(chip.macAddress, isNotEmpty);
    });
  });
}

class ScriptedTransport implements EspTransportInterface {
  ScriptedTransport({
    Map<EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>? handlers,
    this.openError,
    this.changeBaudError,
  }) : handlers = handlers ??
            <EspCommandOpcode, Queue<EspResponse Function(EspCommand)>>{};

  final Map<EspCommandOpcode, Queue<EspResponse Function(EspCommand)>> handlers;
  final Object? openError;
  final Object? changeBaudError;
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> changeBaud(int newBaud) async {
    if (changeBaudError != null) {
      throw changeBaudError!;
    }
  }

  @override
  Future<void> close() async {
    _isOpen = false;
  }

  @override
  Future<void> open(EspConfig config) async {
    if (openError != null) {
      throw openError!;
    }
    _isOpen = true;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command,
      {Duration? timeout}) async {
    final queue = handlers[command.opcode];
    if (queue == null || queue.isEmpty) {
      return _successResponse(command.opcode);
    }
    return queue.removeFirst()(command);
  }
}

class SplitResponseSerialPort implements SerialPortInterface {
  SplitResponseSerialPort({required List<Uint8List> responses})
      : _responses = Queue<Uint8List>.from(responses);

  final Queue<Uint8List> _responses;
  SerialConfig _config = const SerialConfig(portName: 'COM8');
  bool _isOpen = false;

  @override
  SerialConfig get config => _config;

  @override
  Stream<Uint8List> get dataStream => const Stream<Uint8List>.empty();

  @override
  Stream<String> get textStream => const Stream<String>.empty();

  @override
  Stream<SerialError> get errorStream => const Stream<SerialError>.empty();

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> close() async {
    _isOpen = false;
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> open(SerialConfig config) async {
    _config = config;
    _isOpen = true;
  }

  @override
  Future<Uint8List> readSync({Duration? timeout}) =>
      read(1024, timeout: timeout);

  @override
  Future<String> readTextSync({Duration? timeout}) async {
    final bytes = await readSync(timeout: timeout);
    return String.fromCharCodes(bytes);
  }

  @override
  Future<Uint8List> read(int length, {Duration? timeout}) async {
    if (_responses.isEmpty) {
      throw SerialError(
        type: SerialErrorType.timeout,
        message: 'timeout',
      );
    }
    return _responses.removeFirst();
  }

  @override
  Future<String> readUntil(String terminator, {Duration? timeout}) async {
    final bytes = await readSync(timeout: timeout);
    return String.fromCharCodes(bytes);
  }

  @override
  Future<void> resetBuffers() async {}

  @override
  Future<SerialControlSignals> getControlSignals() async =>
      const SerialControlSignals();

  @override
  Future<bool> getCts() async => false;

  @override
  Future<void> setDtr(bool enabled) async {}

  @override
  Future<void> setRts(bool enabled) async {}

  @override
  Future<int> write(Uint8List data, {Duration? timeout}) async => data.length;

  @override
  Future<int> writeText(String data, {Duration? timeout}) async => data.length;

  @override
  Future<int> bytesAvailable() async =>
      _responses.isEmpty ? 0 : _responses.first.length;
}

EspResponse _successResponse(
  EspCommandOpcode opcode, {
  int value = 0,
  Uint8List? data,
  int status = 0,
  int error = 0,
}) {
  return EspResponse(
    opcode: opcode,
    value: value,
    data: data ?? Uint8List(0),
    status: status,
    error: error,
  );
}

Uint8List _buildSlipResponse(EspCommandOpcode opcode) {
  final raw = Uint8List.fromList(<int>[
    0x01,
    opcode.value,
    0x02,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  return SlipCodec.encode(raw);
}
