import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_esptool/src/infrastructure/compression/zlib_helper.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model and utility coverage', () {
    test('EspConfig copy equality hash and string include all fields', () {
      const config = EspConfig(portName: 'COM1');
      final updated = config.copyWith(
        portName: 'COM2',
        initialBaudRate: 74880,
        flashBaudRate: 921600,
        timeout: const Duration(seconds: 9),
        syncRetries: 3,
        flashBlockSize: 1024,
      );

      expect(updated, isNot(config));
      expect(updated, equals(updated.copyWith()));
      expect(updated.hashCode, equals(updated.copyWith().hashCode));
      expect(updated.toString(), contains('COM2'));
      expect(updated.toString(), contains('921600'));
    });

    test('Result factories map fold and state helpers cover both variants', () {
      final success = Result.success<int>(2);
      final mapped = success.map((value) => '$value!');
      expect(success.isSuccess, isTrue);
      expect(success.isFailure, isFalse);
      expect(mapped.fold((value) => value, (_) => 'bad'), '2!');

      const error = EspError(type: EspErrorType.unknown, message: 'boom');
      final failure = Result.failure<int>(error);
      expect(failure.isSuccess, isFalse);
      expect(failure.isFailure, isTrue);
      expect(failure.map((value) => '$value'), isA<Failure<String>>());
      expect(failure.fold((_) => 'bad', (error) => error.message), 'boom');
    });

    test('progress fraction and flash read parameter defaults', () {
      const noTotal = EspProgress(
        stage: EspProgressStage.connecting,
        current: 1,
        total: 0,
        message: 'none',
      );
      const half = EspProgress(
        stage: EspProgressStage.writing,
        current: 2,
        total: 4,
        message: 'half',
      );
      expect(noTotal.fraction, 0);
      expect(half.fraction, 0.5);

      const read = FlashReadParameters(offset: 1, size: 2);
      expect(read.onProgress, isNull);
    });

    test('stub loader reports unavailable stubs', () async {
      final loader = StubLoaderService();
      expect(loader.isLoaded, isFalse);
      final result = await loader.loadStub(ChipFamily.esp32);
      expect(result, isA<Failure<void>>());
      expect(
          (result as Failure<void>).error.type, EspErrorType.stubNotAvailable);
    });

    test('zlib helper compresses, decompresses, and reports invalid data', () {
      final input = Uint8List.fromList(utf8.encode('hello hello hello'));
      final compressed = ZlibHelper.compress(input);
      expect(compressed, isA<Success<Uint8List>>());
      final decompressed = ZlibHelper.decompress(
        (compressed as Success<Uint8List>).value,
      );
      expect((decompressed as Success<Uint8List>).value, input);

      final invalid = ZlibHelper.decompress(Uint8List.fromList(<int>[1, 2, 3]));
      expect(invalid, isA<Failure<Uint8List>>());
      expect((invalid as Failure<Uint8List>).error.type,
          EspErrorType.compressionError);
    });

    test('chip family resolver covers alternate C3 and unknown descriptions',
        () {
      expect(ChipFamilyResolver.resolve(0x001B4F18), ChipFamily.esp32c3);
      expect(ChipFamilyResolver.describe(ChipFamily.unknown),
          'Unknown ESP device');
    });
  });

  group('flash image and partition coverage', () {
    test('image parser covers mode size freq variants and defaults', () {
      for (final mode in <int>[0, 1, 2, 3, 99]) {
        for (final size in <int>[0, 1, 2, 3, 4, 15]) {
          for (final freq in <int>[0, 1, 2, 0x0F, 7]) {
            final result = EspImageParser.parse(_image(mode, size, freq));
            expect(result.isSuccess, isTrue);
            expect((result as Success<EspImageHeader>).value.isValid, isTrue);
          }
        }
      }
    });

    test('image parser reports segment header data and checksum errors', () {
      expect(
          EspImageParser.parse(
              Uint8List.fromList(<int>[0xE9, 1, 0, 0, 0, 0, 0, 0, 0])),
          isA<Failure<EspImageHeader>>());
      expect(
          EspImageParser.parse(Uint8List.fromList(
              <int>[0xE9, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 1])),
          isA<Failure<EspImageHeader>>());
      expect(
          EspImageParser.parse(
              Uint8List.fromList(<int>[0xE9, 0, 0, 0, 0, 0, 0, 0])),
          isA<Failure<EspImageHeader>>());
    });

    test('partition parser covers all type and subtype mappings', () {
      final bytes = BytesBuilder();
      bytes.add(_partition(0x00, 0x00, 'factory', flags: 1));
      bytes.add(_partition(0x00, 0x10, 'ota0'));
      bytes.add(_partition(0x00, 0x11, 'ota1'));
      bytes.add(_partition(0x00, 0x7F, 'appunk'));
      bytes.add(_partition(0x01, 0x02, 'nvs'));
      bytes.add(_partition(0x01, 0x01, 'phy'));
      bytes.add(_partition(0x01, 0x03, 'core'));
      bytes.add(_partition(0x01, 0x82, 'spiffs'));
      bytes.add(_partition(0x01, 0x81, 'fat'));
      bytes.add(_partition(0x01, 0x7F, 'dataunk'));
      bytes.add(_partition(0x40, 0x00, 'unknown'));
      bytes.add(Uint8List(PartitionTable.entrySize)
        ..fillRange(0, PartitionTable.entrySize, 0xFF));

      final result = PartitionTable.parse(bytes.toBytes());
      expect(result.isSuccess, isTrue);
      final entries = (result as Success<List<PartitionEntry>>).value;
      expect(entries.map((entry) => entry.subtype),
          contains(PartitionSubtype.fat));
      expect(entries.first.isEncrypted, isTrue);
      expect(entries.last.type, PartitionType.unknown);
    });

    test('partition parser validates alignment magic and ascii labels', () {
      expect(PartitionTable.parse(Uint8List(1)),
          isA<Failure<List<PartitionEntry>>>());
      expect(PartitionTable.parse(Uint8List(PartitionTable.entrySize)),
          isA<Failure<List<PartitionEntry>>>());
      final badLabel = _partition(0x01, 0x02, 'nvs');
      badLabel[12] = 0xFF;
      badLabel[13] = 0x00;
      expect(
          PartitionTable.parse(badLabel), isA<Failure<List<PartitionEntry>>>());
    });

    test('flash image builder returns aligned and empty inputs unchanged', () {
      expect(FlashImageBuilder.buildPaddedImage(Uint8List(0)), isEmpty);
      final aligned = Uint8List(4);
      expect(
          FlashImageBuilder.buildPaddedImage(aligned, alignment: 4), aligned);
      expect(
          FlashImageBuilder.splitIntoBlocks(Uint8List(0), 0x1000, 4), isEmpty);
    });
  });

  group('flash service coverage', () {
    test('compressed write success sends deflate commands and progress',
        () async {
      final progress = <EspProgress>[];
      final transport = _CommandTransport(success: true);
      final flash = FlashService(transport: transport, blockSize: 8);
      final result = await flash.writeFlash(
        FlashParameters(
          offset: 0x1000,
          data: Uint8List.fromList(<int>[1, 2, 3]),
          compress: true,
          onProgress: (event) {
            progress.add(event);
            return Stream<EspProgress>.value(event);
          },
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
          transport.opcodes,
          containsAll(<EspCommandOpcode>[
            EspCommandOpcode.flashDeflBegin,
            EspCommandOpcode.flashDeflData,
            EspCommandOpcode.flashDeflEnd,
          ]));
      expect(progress.last.stage, EspProgressStage.done);
    });

    test('write flash handles begin data end and thrown failures', () async {
      for (final opcode in <EspCommandOpcode>[
        EspCommandOpcode.flashBegin,
        EspCommandOpcode.flashData,
        EspCommandOpcode.flashEnd,
      ]) {
        final flash = FlashService(
          transport: _CommandTransport(failOpcode: opcode),
          blockSize: 4,
        );
        final result = await flash.writeFlash(
          FlashParameters(offset: 0, data: Uint8List.fromList(<int>[1])),
        );
        expect(result, isA<Failure<void>>());
      }

      final thrown = FlashService(
        transport: _CommandTransport(throwOpcode: EspCommandOpcode.flashBegin),
      );
      final result = await thrown.writeFlash(
        FlashParameters(offset: 0, data: Uint8List.fromList(<int>[1])),
      );
      expect(
          (result as Failure<void>).error.type, EspErrorType.flashWriteFailed);
    });

    test('write verify succeeds when MD5 matches payload', () async {
      final transport =
          _CommandTransport(md5Text: '08d6c05a21512a79a1dfeb9d2a8f262f');
      final flash = FlashService(transport: transport, blockSize: 4);
      final result = await flash.writeFlash(
        FlashParameters(
          offset: 0,
          data: Uint8List.fromList(<int>[1, 2, 3, 4]),
          verify: true,
        ),
      );
      expect(result.isSuccess, isTrue);
    });

    test('read flash validates parameters and device responses', () async {
      final flash = FlashService(transport: _CommandTransport());
      expect(
          await flash.readFlash(const FlashReadParameters(offset: -1, size: 1)),
          isA<Failure<Uint8List>>());

      final success = await flash
          .readFlash(const FlashReadParameters(offset: 0x8000, size: 80));
      expect((success as Success<Uint8List>).value.length, 80);

      final short =
          await FlashService(transport: _CommandTransport(shortRead: true))
              .readFlash(const FlashReadParameters(offset: 0, size: 2));
      expect(short, isA<Failure<Uint8List>>());

      final rejectParams = await FlashService(
        transport: _CommandTransport(failOpcode: EspCommandOpcode.spiSetParams),
      ).readFlash(const FlashReadParameters(offset: 0, size: 1));
      expect((rejectParams as Failure<Uint8List>).error.type,
          EspErrorType.flashReadFailed);

      final rejectRead = await FlashService(
        transport:
            _CommandTransport(failOpcode: EspCommandOpcode.readFlashSlow),
      ).readFlash(const FlashReadParameters(offset: 0, size: 1));
      expect(rejectRead, isA<Failure<Uint8List>>());

      final thrown = await FlashService(
        transport: _CommandTransport(throwOpcode: EspCommandOpcode.spiAttach),
      ).readFlash(const FlashReadParameters(offset: 0, size: 1));
      expect((thrown as Failure<Uint8List>).error.type,
          EspErrorType.flashReadFailed);
    });

    test('erase flash covers full region validation rejection and throws',
        () async {
      expect(await FlashService(transport: _CommandTransport()).eraseFlash(),
          isA<Success<void>>());
      expect(
          await FlashService(transport: _CommandTransport())
              .eraseFlash(offset: 0, size: 4096),
          isA<Success<void>>());
      expect(
          await FlashService(transport: _CommandTransport())
              .eraseFlash(offset: 0),
          isA<Failure<void>>());
      expect(
          await FlashService(transport: _CommandTransport())
              .eraseFlash(offset: -1, size: 1),
          isA<Failure<void>>());
      expect(
          await FlashService(
                  transport: _CommandTransport(
                      failOpcode: EspCommandOpcode.eraseFlash))
              .eraseFlash(),
          isA<Failure<void>>());
      expect(
          await FlashService(
                  transport: _CommandTransport(
                      throwOpcode: EspCommandOpcode.eraseFlash))
              .eraseFlash(),
          isA<Failure<void>>());
    });

    test('md5 flash covers text binary empty rejection and throws', () async {
      final text = await FlashService(
              transport: _CommandTransport(
                  md5Text: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'))
          .md5Flash(0, 1);
      expect(
          (text as Success<String>).value, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

      final binaryBytes =
          Uint8List.fromList(List<int>.generate(16, (index) => index));
      final binary = await FlashService(
              transport: _CommandTransport(md5Bytes: binaryBytes))
          .md5Flash(0, 1);
      expect((binary as Success<String>).value,
          '000102030405060708090a0b0c0d0e0f');

      final verifyMd5Failure = await FlashService(
        transport: _CommandTransport(md5Bytes: Uint8List(0)),
      ).writeFlash(
        FlashParameters(
          offset: 0,
          data: Uint8List.fromList(<int>[1, 2, 3]),
          verify: true,
        ),
      );
      expect(verifyMd5Failure, isA<Failure<void>>());

      expect(
          await FlashService(
                  transport: _CommandTransport(md5Bytes: Uint8List(0)))
              .md5Flash(0, 1),
          isA<Failure<String>>());
      expect(
          await FlashService(
                  transport:
                      _CommandTransport(failOpcode: EspCommandOpcode.flashMd5))
              .md5Flash(0, 1),
          isA<Failure<String>>());
      expect(
          await FlashService(
                  transport:
                      _CommandTransport(throwOpcode: EspCommandOpcode.flashMd5))
              .md5Flash(0, 1),
          isA<Failure<String>>());
    });
  });

  group('info and connection coverage', () {
    test(
        'info service handles detect failure unsupported chip and manufacturers',
        () async {
      final invalid = await InfoService(
        transport: _CommandTransport(readRegisterValue: 0x12345678),
      ).getFlashId();
      expect(invalid, isA<Failure<EspFlashInfo>>());

      final unknownFamily = await InfoService(
        transport: _CommandTransport(),
        chipDetectionService: _FixedChipDetection(ChipFamily.unknown),
      ).getFlashId();
      expect((unknownFamily as Failure<EspFlashInfo>).error.type,
          EspErrorType.unsupportedOperation);

      for (final id in <int>[0x1C, 0x20, 0xA1, 0xC2, 0xC8, 0xEF, 0x99]) {
        final result = await InfoService(
          transport:
              _CommandTransport(jedecId: id | (0x40 << 8) | (0x10 << 16)),
        ).getFlashId();
        expect(result.isSuccess, isTrue);
      }

      expect(
          (await InfoService(transport: _CommandTransport()).getChipInfo())
              .isSuccess,
          isTrue);

      for (final magic in <int>[
        0xFFF0C101,
        0x000007C6,
        0x00000009,
        0x6921506F
      ]) {
        final result = await InfoService(
          transport: _CommandTransport(readRegisterValue: magic),
        ).getFlashId();
        expect(result.isSuccess, isTrue);
      }

      final readFailure = await InfoService(
        transport: _CommandTransport(failReadRegisterAfterDetect: true),
      ).getFlashId();
      expect(readFailure, isA<Failure<EspFlashInfo>>());

      final writeFailure = await InfoService(
        transport: _CommandTransport(failOpcode: EspCommandOpcode.writeReg),
      ).getFlashId();
      expect(writeFailure, isA<Failure<EspFlashInfo>>());
    });

    test('connection service disconnect and non-Esp errors are mapped',
        () async {
      final transport = _CommandTransport();
      final connection = ConnectionService(transport);
      await connection.disconnect();
      expect(connection.isConnected, isFalse);

      final result = await ConnectionService(
              _CommandTransport(openThrowsObject: StateError('x')))
          .connect(const EspConfig(portName: 'COM1'));
      expect(
          (result as Failure<void>).error.type, EspErrorType.connectionFailed);

      final timeout = await ConnectionService(_CommandTransport(
        openThrowsObject:
            SerialError(type: SerialErrorType.timeout, message: 'slow'),
      )).connect(const EspConfig(portName: 'COM1'));
      expect((timeout as Failure<void>).error.type, EspErrorType.timeout);

      final syncEspErrors = await ConnectionService(_CommandTransport(
        throwOpcode: EspCommandOpcode.sync,
      )).connect(const EspConfig(portName: 'COM1', syncRetries: 1));
      expect(syncEspErrors, isA<Failure<void>>());

      final chipResponseError = await ChipDetectionService(
        _CommandTransport(failOpcode: EspCommandOpcode.readReg),
      ).detect();
      expect((chipResponseError as Failure<EspChipInfo>).error.type,
          EspErrorType.invalidResponse);

      final chipNonEspError = await ChipDetectionService(
        _CommandTransport(throwOpcode: EspCommandOpcode.readReg),
      ).detect();
      expect((chipNonEspError as Failure<EspChipInfo>).error.type,
          EspErrorType.invalidChip);
    });
  });

  group('transport coverage', () {
    test('resetToBootloader requires open port and supports platform fallback',
        () async {
      final defaultTransport = EspTransport();
      expect(defaultTransport.isOpen, isFalse);

      final closed = EspTransport(serial: _Serial());
      expect(closed.isOpen, isFalse);
      expect(closed.resetToBootloader, throwsA(isA<EspError>()));

      final normalSerial = _Serial();
      final normalTransport = EspTransport(serial: normalSerial);
      await normalTransport.open(const EspConfig(portName: 'COM1'));
      await normalTransport.resetToBootloader();
      await normalTransport.close();
      expect(normalTransport.isOpen, isFalse);
      await normalTransport.close();

      final fallbackSerial = _Serial(platformUnavailableSignals: true);
      final transport = EspTransport(serial: fallbackSerial);
      await transport.open(const EspConfig(portName: 'COM1'));
      await transport.resetToBootloader();
      expect(fallbackSerial.emptyWrites, 4);
    });

    test('transport maps serial write errors and logs transport errors',
        () async {
      final successLogs = <EspTransportLogEntry>[];
      final successTransport = EspTransport(
        serial: _Serial(
            responses: <Uint8List>[_slipResponse(EspCommandOpcode.sync)]),
        logger: successLogs.add,
      );
      await successTransport.open(const EspConfig(portName: 'COM1'));
      final success = await successTransport
          .sendCommand(EspCommand(opcode: EspCommandOpcode.sync));
      expect(success.isSuccess, isTrue);
      expect(
          successLogs.any(
              (entry) => entry.type == EspTransportLogType.responseReceived),
          isTrue);

      final logs = <EspTransportLogEntry>[];
      final serial = _Serial(
          writeError: SerialError(
              type: SerialErrorType.portNotFound, message: 'missing'));
      final transport = EspTransport(serial: serial, logger: logs.add);
      await transport.open(const EspConfig(portName: 'COM1'));
      await expectLater(
          transport.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
          throwsA(isA<EspError>().having(
              (error) => error.type, 'type', EspErrorType.portUnavailable)));
      expect(
          logs.any((entry) => entry.type == EspTransportLogType.transportError),
          isTrue);
    });

    test('transport rejects malformed response packets', () async {
      for (final frame in <Uint8List>[
        SlipCodec.encode(Uint8List.fromList(<int>[1, 2, 3])),
        SlipCodec.encode(Uint8List.fromList(
            <int>[0, EspCommandOpcode.sync.value, 2, 0, 0, 0, 0, 0, 0, 0])),
        SlipCodec.encode(
            Uint8List.fromList(<int>[1, 0xFE, 2, 0, 0, 0, 0, 0, 0, 0])),
        SlipCodec.encode(Uint8List.fromList(
            <int>[1, EspCommandOpcode.sync.value, 0, 0, 0, 0, 0, 0, 0])),
      ]) {
        final transport = EspTransport(
          serial: _Serial(responses: <Uint8List>[frame]),
          logger: (_) {},
        );
        await transport.open(const EspConfig(portName: 'COM1'));
        await expectLater(
            transport.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
            throwsA(isA<EspError>().having(
                (error) => error.type, 'type', EspErrorType.invalidResponse)));
      }
    });

    test('transport discards noise and reports partial trailing frames',
        () async {
      final mappedReadError = EspTransport(
        serial: _Serial(
            readError: SerialError(
                type: SerialErrorType.permissionDenied, message: 'denied')),
      );
      await mappedReadError.open(const EspConfig(portName: 'COM1'));
      await expectLater(
          mappedReadError
              .sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
          throwsA(isA<EspError>().having(
              (error) => error.type, 'type', EspErrorType.connectionFailed)));

      final noiseOnly = EspTransport(
        serial: _Serial(responses: <Uint8List>[
          Uint8List.fromList(<int>[1, 2, 3])
        ]),
      );
      await noiseOnly.open(const EspConfig(
          portName: 'COM1', timeout: Duration(milliseconds: 1)));
      await expectLater(
          noiseOnly.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
          throwsA(isA<EspError>()
              .having((error) => error.type, 'type', EspErrorType.timeout)));

      final frameWithRemaining = EspTransport(
        serial: _Serial(responses: <Uint8List>[
          Uint8List.fromList(<int>[
            ..._slipResponse(EspCommandOpcode.sync),
            0x99,
          ])
        ]),
      );
      await frameWithRemaining.open(const EspConfig(portName: 'COM1'));
      expect(
        (await frameWithRemaining
                .sendCommand(EspCommand(opcode: EspCommandOpcode.sync)))
            .isSuccess,
        isTrue,
      );

      final split = _slipResponse(EspCommandOpcode.sync);
      final trimmedNoise = EspTransport(
        serial: _Serial(responses: <Uint8List>[
          Uint8List.fromList(<int>[0x01, 0x02, ...split.sublist(0, 5)]),
          Uint8List.fromList(split.sublist(5)),
        ]),
      );
      await trimmedNoise.open(const EspConfig(portName: 'COM1'));
      expect(
        (await trimmedNoise
                .sendCommand(EspCommand(opcode: EspCommandOpcode.sync)))
            .isSuccess,
        isTrue,
      );

      final serial = _Serial(responses: <Uint8List>[
        Uint8List.fromList(<int>[1, 2, 3, 0xC0, 1, 2])
      ]);
      final transport = EspTransport(serial: serial);
      await transport.open(const EspConfig(
          portName: 'COM1', timeout: Duration(milliseconds: 1)));
      await expectLater(
          transport.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
          throwsA(isA<EspError>().having((error) => error.type, 'type',
              anyOf(EspErrorType.partialPacket, EspErrorType.timeout))));
    });
  });
}

Uint8List _image(int mode, int sizeNibble, int freqNibble) {
  final bytes = BytesBuilder();
  bytes.add(<int>[espImageMagic, 1, mode, (sizeNibble << 4) | freqNibble]);
  final header = Uint8List(4)
    ..buffer.asByteData().setUint32(0, 0x40000000, Endian.little);
  bytes.add(header);
  final segHeader = Uint8List(8);
  final segData = segHeader.buffer.asByteData();
  segData.setUint32(0, 0x3f400020, Endian.little);
  segData.setUint32(4, 2, Endian.little);
  bytes.add(segHeader);
  bytes.add(<int>[0x12, 0x34]);
  bytes.add(<int>[0xEF ^ 0x12 ^ 0x34]);
  return bytes.toBytes();
}

Uint8List _partition(int type, int subtype, String label, {int flags = 0}) {
  final bytes = Uint8List(PartitionTable.entrySize);
  final data = ByteData.sublistView(bytes);
  bytes[0] = PartitionTable.magic1;
  bytes[1] = PartitionTable.magic2;
  bytes[2] = type;
  bytes[3] = subtype;
  data.setUint32(4, 0x9000, Endian.little);
  data.setUint32(8, 0x1000, Endian.little);
  final labelBytes = ascii.encode(label);
  bytes.setRange(12, 12 + labelBytes.length.clamp(0, 16), labelBytes.take(16));
  data.setUint32(28, flags, Endian.little);
  return bytes;
}

class _FixedChipDetection extends ChipDetectionService {
  _FixedChipDetection(this.family) : super(_CommandTransport());

  final ChipFamily family;

  @override
  Future<Result<EspChipInfo>> detect() async {
    return Success<EspChipInfo>(
      EspChipInfo(
        family: family,
        description: ChipFamilyResolver.describe(family),
        magicValue: 0,
        macAddress: '00:00:00:00:00:00',
      ),
    );
  }
}

class _CommandTransport implements EspTransportInterface {
  _CommandTransport({
    this.failOpcode,
    this.throwOpcode,
    this.md5Text,
    this.md5Bytes,
    this.shortRead = false,
    this.failReadRegisterAfterDetect = false,
    this.readRegisterValue = 0x00F01D83,
    this.jedecId = 0x001840EF,
    this.openThrowsObject,
    bool success = true,
  }) : _success = success;

  final EspCommandOpcode? failOpcode;
  final EspCommandOpcode? throwOpcode;
  final String? md5Text;
  final Uint8List? md5Bytes;
  final bool shortRead;
  final bool failReadRegisterAfterDetect;
  final int readRegisterValue;
  final int jedecId;
  final Object? openThrowsObject;
  final bool _success;
  final List<EspCommandOpcode> opcodes = <EspCommandOpcode>[];
  bool _open = true;
  int _readRegCount = 0;
  int _spiBusyReads = 0;

  @override
  bool get isOpen => _open;

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  Future<void> open(EspConfig config) async {
    if (openThrowsObject != null) {
      throw openThrowsObject!;
    }
    _open = true;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command,
      {Duration? timeout}) async {
    opcodes.add(command.opcode);
    if (command.opcode == throwOpcode) {
      throw StateError('boom');
    }
    if (command.opcode == failOpcode || !_success) {
      return _response(command.opcode, status: 1);
    }
    switch (command.opcode) {
      case EspCommandOpcode.readReg:
        _readRegCount++;
        if (failReadRegisterAfterDetect && _readRegCount > 4) {
          return _response(command.opcode, status: 1);
        }
        if (_readRegCount == 1) {
          return _response(command.opcode, value: readRegisterValue);
        }
        final address =
            ByteData.sublistView(command.data).getUint32(0, Endian.little);
        if (address == 0x3FF42000) {
          _spiBusyReads++;
          return _response(command.opcode,
              value: _spiBusyReads == 1 ? (1 << 18) : 0);
        }
        if (address == 0x3FF42080) {
          return _response(command.opcode, value: jedecId);
        }
        return _response(command.opcode, value: 0x11223344);
      case EspCommandOpcode.readFlashSlow:
        final size =
            ByteData.sublistView(command.data).getUint32(4, Endian.little);
        return _response(
          command.opcode,
          data: Uint8List(shortRead ? 0 : size)
            ..fillRange(0, shortRead ? 0 : size, 0xAA),
        );
      case EspCommandOpcode.flashMd5:
        if (md5Text != null) {
          return _response(command.opcode,
              data: Uint8List.fromList(md5Text!.codeUnits));
        }
        return _response(command.opcode,
            data: md5Bytes ??
                Uint8List.fromList(
                    'deadbeefdeadbeefdeadbeefdeadbeef'.codeUnits));
      default:
        return _response(command.opcode);
    }
  }
}

class _Serial implements SerialPortInterface {
  _Serial({
    List<Uint8List>? responses,
    this.writeError,
    this.readError,
    this.platformUnavailableSignals = false,
  }) : _responses = Queue<Uint8List>.from(responses ?? const <Uint8List>[]);

  final Queue<Uint8List> _responses;
  final SerialError? writeError;
  final SerialError? readError;
  final bool platformUnavailableSignals;
  int emptyWrites = 0;
  bool _open = false;
  SerialConfig _config = const SerialConfig(portName: 'COM1');

  @override
  SerialConfig get config => _config;
  @override
  Stream<Uint8List> get dataStream => const Stream<Uint8List>.empty();
  @override
  Stream<SerialError> get errorStream => const Stream<SerialError>.empty();
  @override
  bool get isOpen => _open;
  @override
  Stream<String> get textStream => const Stream<String>.empty();

  @override
  Future<int> bytesAvailable() async =>
      _responses.isEmpty ? 0 : _responses.first.length;
  @override
  Future<void> close() async => _open = false;
  @override
  Future<void> flush() async {}
  @override
  Future<SerialControlSignals> getControlSignals() async =>
      const SerialControlSignals();
  @override
  Future<bool> getCts() async => false;
  @override
  Future<void> open(SerialConfig config) async {
    _config = config;
    _open = true;
  }

  @override
  Future<Uint8List> read(int length, {Duration? timeout}) async {
    if (readError != null) {
      throw readError!;
    }
    if (_responses.isEmpty) {
      throw SerialError(type: SerialErrorType.timeout, message: 'timeout');
    }
    return _responses.removeFirst();
  }

  @override
  Future<Uint8List> readSync({Duration? timeout}) => read(1, timeout: timeout);
  @override
  Future<String> readTextSync({Duration? timeout}) async =>
      String.fromCharCodes(await readSync(timeout: timeout));
  @override
  Future<String> readUntil(String terminator, {Duration? timeout}) async =>
      String.fromCharCodes(await readSync(timeout: timeout));
  @override
  Future<void> resetBuffers() async {}
  @override
  Future<void> setDtr(bool enabled) async {
    if (platformUnavailableSignals) {
      throw SerialError(
          type: SerialErrorType.platformUnavailable, message: 'no dtr');
    }
  }

  @override
  Future<void> setRts(bool enabled) async {}
  @override
  Future<int> write(Uint8List data, {Duration? timeout}) async {
    if (writeError != null) {
      throw writeError!;
    }
    if (data.isEmpty) {
      emptyWrites++;
    }
    return data.length;
  }

  @override
  Future<int> writeText(String data, {Duration? timeout}) async => data.length;
}

Uint8List _slipResponse(EspCommandOpcode opcode) {
  return SlipCodec.encode(Uint8List.fromList(<int>[
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
  ]));
}

EspResponse _response(EspCommandOpcode opcode,
    {int value = 0, Uint8List? data, int status = 0}) {
  return EspResponse(
    opcode: opcode,
    value: value,
    data: data ?? Uint8List(0),
    status: status,
    error: 0,
  );
}
