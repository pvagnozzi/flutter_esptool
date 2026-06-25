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
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('command utils', () {
    test(
      'parseFlexibleInt parses decimal, hex, and defaults on invalid input',
      () {
        expect(parseFlexibleInt('42', defaultValue: -1), 42);
        expect(parseFlexibleInt(' 0x1f ', defaultValue: -1), 31);
        expect(parseFlexibleInt('bad-value', defaultValue: 77), 77);
      },
    );

    test('requirePort trims parsed port values', () async {
      final command = _CapturePortCommand();
      final runner = CommandRunner<void>('test', 'test')..addCommand(command);

      await runner.run(<String>['capture_port', '--port', '  COM77  ']);
      expect(command.capturedPort, 'COM77');
    });

    test('requirePort throws when missing or blank', () async {
      final runnerMissing = CommandRunner<void>('test', 'test')
        ..addCommand(_CapturePortCommand());
      await expectLater(
        runnerMissing.run(<String>['capture_port']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('Missing option "port".'),
          ),
        ),
      );

      final runnerBlank = CommandRunner<void>('test', 'test')
        ..addCommand(_CapturePortCommand());
      await expectLater(
        runnerBlank.run(<String>['capture_port', '--port', '   ']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('Missing option "port".'),
          ),
        ),
      );
    });
  });

  group('command contracts', () {
    test('all commands expose stable names and descriptions', () {
      expect(ChipIdCommand().name, 'chip_id');
      expect(ChipIdCommand().description, 'Read chip ID and MAC address');

      expect(ReadMacCommand().name, 'read_mac');
      expect(ReadMacCommand().description, 'Read WiFi and BT MAC addresses');

      expect(FlashIdCommand().name, 'flash_id');
      expect(FlashIdCommand().description, 'Read SPI flash ID');

      expect(EraseFlashCommand().name, 'erase_flash');
      expect(EraseFlashCommand().description, 'Erase entire flash');

      expect(EraseRegionCommand().name, 'erase_region');
      expect(EraseRegionCommand().description, 'Erase a region of flash');

      expect(ReadFlashCommand().name, 'read_flash');
      expect(ReadFlashCommand().description, 'Read binary from flash');

      expect(WriteFlashCommand().name, 'write_flash');
      expect(WriteFlashCommand().description, 'Write binary to flash');

      expect(VersionCommand().name, 'version');
      expect(VersionCommand().description, 'Show esptool version');
    });

    test('hardware commands keep expected option contracts', () {
      final chip = ChipIdCommand();
      expect(chip.argParser.options['port']?.mandatory, isTrue);
      expect(chip.argParser.options['baud']?.defaultsTo, '115200');
      expect(chip.argParser.options['timeout']?.defaultsTo, '10');

      final readMac = ReadMacCommand();
      expect(readMac.argParser.options['port']?.mandatory, isTrue);
      expect(readMac.argParser.options['baud']?.defaultsTo, '115200');
      expect(readMac.argParser.options['timeout']?.defaultsTo, '10');

      final flashId = FlashIdCommand();
      expect(flashId.argParser.options['port']?.mandatory, isTrue);
      expect(flashId.argParser.options['baud']?.defaultsTo, '115200');
      expect(flashId.argParser.options['timeout']?.defaultsTo, '10');

      final eraseFlash = EraseFlashCommand();
      expect(eraseFlash.argParser.options['port']?.mandatory, isTrue);
      expect(eraseFlash.argParser.options['baud']?.defaultsTo, '115200');

      final eraseRegion = EraseRegionCommand();
      expect(eraseRegion.argParser.options['port']?.mandatory, isTrue);
      expect(eraseRegion.argParser.options['address']?.mandatory, isTrue);
      expect(eraseRegion.argParser.options['length']?.mandatory, isTrue);
      expect(eraseRegion.argParser.options['baud']?.defaultsTo, '115200');

      final readFlash = ReadFlashCommand();
      expect(readFlash.argParser.options['port']?.mandatory, isTrue);
      expect(readFlash.argParser.options['address']?.defaultsTo, '0x0');
      expect(readFlash.argParser.options['length']?.defaultsTo, '0x100');
      expect(readFlash.argParser.options['timeout']?.defaultsTo, '15');
      expect(readFlash.argParser.options['baud']?.defaultsTo, '115200');

      final writeFlash = WriteFlashCommand();
      expect(writeFlash.argParser.options['port']?.mandatory, isTrue);
      expect(writeFlash.argParser.options['address']?.defaultsTo, '0x1000');
      expect(writeFlash.argParser.options['baud']?.defaultsTo, '115200');
      expect(writeFlash.argParser.options['verify']?.defaultsTo, true);
    });
  });
}

class _CapturePortCommand extends Command<void> {
  _CapturePortCommand() {
    argParser.addOption('port');
  }

  String? capturedPort;

  @override
  String get name => 'capture_port';

  @override
  String get description => 'Capture parsed port for tests';

  @override
  void run() {
    capturedPort = requirePort(this);
  }
}
