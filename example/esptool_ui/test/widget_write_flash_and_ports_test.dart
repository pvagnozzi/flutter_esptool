import 'dart:typed_data';

import 'package:esptool_ui/main.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'write flash supports add/select/remove rows and completes flashing',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      var pickCount = 0;
      Future<XFile?> pickFile() async {
        pickCount++;
        return XFile.fromData(
          Uint8List.fromList(<int>[1, 2, 3, pickCount]),
          name: 'firmware_$pickCount.bin',
        );
      }

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM50',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (logger) => _LoggingTransport(logger: logger),
          binFilePicker: pickFile,
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add binary'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select .bin').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select .bin').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Flash write completed for'), findsOneWidget);
      expect(pickCount, 2);
    },
  );

  testWidgets(
    'write flash cancel path logs cancellation and does not start write',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM51',
              description: 'Mock',
              platform: 'windows',
            ),
          ],
          transportFactory: (logger) => _LoggingTransport(logger: logger),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Flash write cancelled'), findsOneWidget);
      expect(find.textContaining('Flash write completed for'), findsNothing);
    },
  );

  testWidgets(
    'changing selected port after connect disconnects and logs selection',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(
              portName: 'COM60',
              description: 'Adapter A',
              platform: 'windows',
            ),
            SerialPortInfo(
              portName: 'COM61',
              description: 'Adapter B',
              platform: 'windows',
            ),
          ],
          transportFactory: (logger) => _LoggingTransport(logger: logger),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('COM61 - Adapter B').last);
      await tester.pumpAndSettle();

      expect(find.text('Selected serial port: COM61'), findsOneWidget);
      final detectButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Detect chip'),
      );
      expect(detectButton.onPressed, isNull);
    },
  );

  testWidgets(
    'compact layout popup menus change locale and theme',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 640));

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(portName: 'COM62', description: '', platform: 'windows'),
          ],
          transportFactory: (logger) => _LoggingTransport(logger: logger),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<Locale>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Italiano').last);
      await tester.pumpAndSettle();
      expect(find.text('Demo Professionale ESP Tool'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<ThemeMode>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scuro').last);
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    },
  );

  testWidgets(
    'operation failures are logged for mac, flash info, erase, md5 and write',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      Future<XFile?> pickFile() async => XFile.fromData(
            Uint8List.fromList(<int>[9, 8, 7, 6]),
            name: 'failure_case.bin',
          );

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: () async => const <SerialPortInfo>[
            SerialPortInfo(portName: 'COM63', description: 'Mock', platform: 'windows'),
          ],
          transportFactory: (logger) => _LoggingTransport(
            logger: logger,
            failReadReg: true,
            failEraseFlash: true,
            failFlashData: true,
            failFlashMd5: true,
          ),
          binFilePicker: pickFile,
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read MAC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flash info'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read MD5'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write flash'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select .bin').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Flash write failed for'), findsOneWidget);
    },
  );

  testWidgets(
    'refresh and port-switch flows cover disconnect warning and error branches',
    (WidgetTester tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1100, 900));

      var call = 0;
      Future<List<SerialPortInfo>> loader() async {
        call++;
        if (call == 1) {
          return const <SerialPortInfo>[
            SerialPortInfo(portName: 'COM64', description: '', platform: 'windows'),
            SerialPortInfo(portName: 'COM65', description: 'Adapter', platform: 'windows'),
          ];
        }
        if (call == 2) {
          return const <SerialPortInfo>[
            SerialPortInfo(portName: 'COM64', description: '', platform: 'windows'),
            SerialPortInfo(portName: 'COM66', description: 'Changed', platform: 'windows'),
          ];
        }
        throw SerialError(type: SerialErrorType.timeout, message: 'refresh timeout');
      }

      await tester.pumpWidget(
        EsptoolUiApp(
          splashDuration: Duration.zero,
          serialPortsLoader: loader,
          transportFactory: (logger) => _LoggingTransport(
            logger: logger,
            throwOnClose: true,
            longFrames: true,
            nullTransportErrorMessage: true,
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('COM64'), findsOneWidget);

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('COM65 - Adapter').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Disconnect warning:'), findsOneWidget);

      await tester.tap(find.byTooltip('Refresh ports').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Refresh ports').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load serial ports:'), findsOneWidget);
      expect(find.textContaining('Disconnect warning:'), findsWidgets);
    },
  );
}

class _LoggingTransport implements EspTransportInterface {
  _LoggingTransport({
    this.logger,
    this.throwOnClose = false,
    this.failReadReg = false,
    this.failEraseFlash = false,
    this.failFlashData = false,
    this.failFlashMd5 = false,
    this.longFrames = false,
    this.nullTransportErrorMessage = false,
    this.jedecRawId = 0x1840EF,
  });

  final EspTransportLogger? logger;
  final bool throwOnClose;
  final bool failReadReg;
  final bool failEraseFlash;
  final bool failFlashData;
  final bool failFlashMd5;
  final bool longFrames;
  final bool nullTransportErrorMessage;
  final int jedecRawId;
  bool _open = false;
  bool _closeFailedOnce = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<void> close() async {
    if (throwOnClose && !_closeFailedOnce) {
      _closeFailedOnce = true;
      throw StateError('close failed');
    }
    _open = false;
  }

  @override
  Future<void> open(EspConfig config) async {
    _open = true;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) async {
    final packet = longFrames
        ? Uint8List.fromList(List<int>.generate(160, (i) => i & 0xFF))
        : Uint8List.fromList(<int>[0x01, 0x02, 0x03]);
    final frame = longFrames
        ? Uint8List.fromList(
            <int>[0xC0, ...List<int>.generate(170, (i) => i & 0xFF), 0xC0],
          )
        : Uint8List.fromList(<int>[0xC0, 0x01, 0xC0]);
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.commandSent,
        timestamp: DateTime.now(),
        opcode: command.opcode,
        command: command,
        rawPacket: packet,
        rawFrame: frame,
      ),
    );

    final response = switch (command.opcode) {
      EspCommandOpcode.readReg => _readRegister(command),
      EspCommandOpcode.flashData when failFlashData => _error(command.opcode),
      EspCommandOpcode.eraseFlash when failEraseFlash => _error(command.opcode),
      EspCommandOpcode.flashMd5 when failFlashMd5 => _error(command.opcode),
      _ => _ok(command.opcode),
    };
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.responseReceived,
        timestamp: DateTime.now(),
        opcode: command.opcode,
        response: response,
        rawPacket: Uint8List.fromList(<int>[0x00, 0x00]),
        rawFrame: Uint8List.fromList(<int>[0xC0, 0x00, 0xC0]),
      ),
    );
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.transportError,
        timestamp: DateTime.now(),
        opcode: command.opcode,
        message:
            nullTransportErrorMessage ? null : 'simulated transport warning',
      ),
    );

    return response;
  }

  EspResponse _readRegister(EspCommand command) {
    if (failReadReg) {
      return _error(command.opcode);
    }
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
      0x3FF42080 => jedecRawId,
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
