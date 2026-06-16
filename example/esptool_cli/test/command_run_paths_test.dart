import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/chip_id_command.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:esptool_cli/src/commands/erase_flash_command.dart';
import 'package:esptool_cli/src/commands/erase_region_command.dart';
import 'package:esptool_cli/src/commands/flash_id_command.dart';
import 'package:esptool_cli/src/commands/read_flash_command.dart';
import 'package:esptool_cli/src/commands/read_mac_command.dart';
import 'package:esptool_cli/src/commands/version_command.dart';
import 'package:esptool_cli/src/commands/write_flash_command.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    setExitHandlerForTesting((code) => throw CommandExit(code));
  });

  tearDown(resetExitHandlerForTesting);

  group('command run paths', () {
    test('chip_id succeeds with scripted transport', () async {
      await _runCommand(
        ChipIdCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9'],
      );
    });

    test('chip_id exits when detection fails', () async {
      await expectLater(
        _runCommand(
          ChipIdCommand(
            transportFactory: () => _ScriptedTransport(failReadReg: true),
          ),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('read_mac succeeds with scripted transport', () async {
      await _runCommand(
        ReadMacCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9'],
      );
    });

    test('read_mac exits on command exception path', () async {
      await expectLater(
        _runCommand(
          ReadMacCommand(
            transportFactory: () => _ScriptedTransport(throwOnCommand: true),
          ),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('read_mac exits when chip detection returns failure', () async {
      await expectLater(
        _runCommand(
          ReadMacCommand(
            transportFactory: () => _ScriptedTransport(failReadReg: true),
          ),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('flash_id succeeds with scripted transport', () async {
      await _runCommand(
        FlashIdCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9'],
      );
    });

    test('flash_id exits on failure response', () async {
      await expectLater(
        _runCommand(
          FlashIdCommand(
            transportFactory: () => _ScriptedTransport(failWriteReg: true),
          ),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('erase_flash succeeds and failure path exits', () async {
      await _runCommand(
        EraseFlashCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9'],
      );

      await expectLater(
        _runCommand(
          EraseFlashCommand(
            transportFactory: () => _ScriptedTransport(failEraseFlash: true),
          ),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('erase_region succeeds and invalid region exits', () async {
      await _runCommand(
        EraseRegionCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9', '--address', '0x1000', '--length', '4096'],
      );

      await expectLater(
        _runCommand(
          EraseRegionCommand(transportFactory: () => _ScriptedTransport()),
          <String>['--port', 'COM9', '--address', '-1', '--length', '0'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('read_flash exits for missing filename', () async {
      await expectLater(
        _runCommand(
          ReadFlashCommand(transportFactory: () => _ScriptedTransport()),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('read_flash succeeds and exits when device rejects read', () async {
      final tempDir = Directory.systemTemp.createTempSync('esptool_cli_read_');
      final outputFile =
          '${tempDir.path}${Platform.pathSeparator}flash_dump.bin';
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      await _runCommand(
        ReadFlashCommand(
          transportFactory: () => _ScriptedTransport(readFlashPayload: 64),
        ),
        <String>[
          '--port',
          'COM9',
          '--filename',
          outputFile,
          '--length',
          '0x40',
        ],
      );
      expect(File(outputFile).existsSync(), isTrue);
      expect(File(outputFile).readAsBytesSync().length, 64);

      await expectLater(
        _runCommand(
          ReadFlashCommand(
            transportFactory: () => _ScriptedTransport(failReadFlash: true),
          ),
          <String>[
            '--port',
            'COM9',
            '--filename',
            outputFile,
            '--length',
            '0x40',
          ],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('write_flash exits for missing filename and missing file', () async {
      await expectLater(
        _runCommand(
          WriteFlashCommand(transportFactory: () => _ScriptedTransport()),
          <String>['--port', 'COM9'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );

      await expectLater(
        _runCommand(
          WriteFlashCommand(transportFactory: () => _ScriptedTransport()),
          <String>['--port', 'COM9', '--filename', 'not-existing.bin'],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('write_flash succeeds and exits on flash failure', () async {
      final tempDir = Directory.systemTemp.createTempSync('esptool_cli_test_');
      final file = File('${tempDir.path}${Platform.pathSeparator}sample.bin')
        ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);

      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      await _runCommand(
        WriteFlashCommand(transportFactory: () => _ScriptedTransport()),
        <String>['--port', 'COM9', '--filename', file.path, '--no-verify'],
      );

      await expectLater(
        _runCommand(
          WriteFlashCommand(
            transportFactory: () => _ScriptedTransport(failFlashData: true),
          ),
          <String>['--port', 'COM9', '--filename', file.path],
        ),
        throwsA(isA<CommandExit>().having((error) => error.code, 'code', 1)),
      );
    });

    test('version command runs', () async {
      await _runCommand(VersionCommand(), const <String>[]);
    });
  });
}

Future<void> _runCommand(Command<void> command, List<String> args) async {
  final runner = CommandRunner<void>('esptool', 'test')..addCommand(command);
  await runner.run(<String>[command.name, ...args]);
}

class _ScriptedTransport implements EspTransportInterface {
  _ScriptedTransport({
    this.failReadReg = false,
    this.failWriteReg = false,
    this.failEraseFlash = false,
    this.failFlashData = false,
    this.failReadFlash = false,
    this.throwOnCommand = false,
    this.readFlashPayload = 0,
  });

  final bool failReadReg;
  final bool failWriteReg;
  final bool failEraseFlash;
  final bool failFlashData;
  final bool failReadFlash;
  final bool throwOnCommand;
  final int readFlashPayload;
  bool _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<void> close() async {
    _isOpen = false;
  }

  @override
  Future<void> open(EspConfig config) async {
    _isOpen = true;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) async {
    if (throwOnCommand) {
      throw StateError('scripted command failure');
    }
    switch (command.opcode) {
      case EspCommandOpcode.sync:
        return _ok(command.opcode);
      case EspCommandOpcode.readReg:
        if (failReadReg) {
          return _error(command.opcode);
        }
        return _readRegister(command);
      case EspCommandOpcode.writeReg:
        return failWriteReg ? _error(command.opcode) : _ok(command.opcode);
      case EspCommandOpcode.eraseFlash:
        return failEraseFlash ? _error(command.opcode) : _ok(command.opcode);
      case EspCommandOpcode.eraseRegion:
        return _ok(command.opcode);
      case EspCommandOpcode.flashData:
        return failFlashData ? _error(command.opcode) : _ok(command.opcode);
      case EspCommandOpcode.readFlashSlow:
        if (failReadFlash) {
          return _error(command.opcode);
        }
        final requested =
            ByteData.sublistView(command.data).getUint32(4, Endian.little);
        final size = readFlashPayload > 0 ? readFlashPayload : requested;
        return EspResponse(
          opcode: command.opcode,
          value: 0,
          data: Uint8List.fromList(List<int>.generate(size, (i) => i & 0xFF)),
          status: 0,
          error: 0,
        );
      default:
        return _ok(command.opcode);
    }
  }

  EspResponse _readRegister(EspCommand command) {
    final address =
        ByteData.sublistView(command.data).getUint32(0, Endian.little);
    final value = switch (address) {
      0x40001000 => 0x00F01D83,
      0x3FF5A00C => 1,
      0x3FF5A008 => 0xAABBCCDD,
      0x3FF5A004 => 0xEEFF0011,
      0x3FF4201C => 0,
      0x3FF42024 => 0,
      0x3FF42000 => 0,
      0x3FF42080 => 0x1840EF,
      _ => 0,
    };
    return EspResponse(
      opcode: command.opcode,
      value: value,
      data: Uint8List(0),
      status: 0,
      error: 0,
    );
  }

  EspResponse _ok(EspCommandOpcode opcode) => EspResponse(
        opcode: opcode,
        value: 0,
        data: Uint8List(0),
        status: 0,
        error: 0,
      );

  EspResponse _error(EspCommandOpcode opcode) => EspResponse(
        opcode: opcode,
        value: 0,
        data: Uint8List(0),
        status: 1,
        error: 1,
      );
}
