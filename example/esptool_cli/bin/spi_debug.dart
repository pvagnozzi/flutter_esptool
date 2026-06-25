// Debug script: test SPI direct flash read step by step
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? args[0] : 'COM22';
  stdout.writeln('Connecting to $port...');

  final transport = EspTransport(
    logger: (entry) {
      final opName = entry.command?.opcode.name ?? '?';
      if (entry.type == EspTransportLogType.commandSent) {
        stdout.writeln('  SEND: $opName');
      } else if (entry.type == EspTransportLogType.responseReceived) {
        final ok = entry.response?.isSuccess ?? false;
        stdout.writeln(
          '  RECV: ${entry.response?.opcode.name ?? "?"} ok=$ok '
          'val=0x${(entry.response?.value ?? 0).toRadixString(16)}',
        );
      } else if (entry.type == EspTransportLogType.transportError) {
        stdout.writeln('  ERR:  $opName ${entry.message}');
      }
    },
  );

  final config = EspConfig(
    portName: port,
    initialBaudRate: 115200,
    timeout: const Duration(seconds: 12),
    syncRetries: 16,
  );

  try {
    final connection = ConnectionService(transport);
    final connectResult = await connection.connect(config);
    if (connectResult.isFailure) {
      stderr.writeln(
        'Connect failed: ${(connectResult as Failure<void>).error.message}',
      );
      exit(1);
    }
    stdout.writeln('Connected!');

    // 1. Detect chip family
    stdout.writeln('\n--- Detect chip ---');
    final detection = ChipDetectionService(transport);
    final chipResult = await detection.detect();
    if (chipResult.isFailure) {
      stderr.writeln('Detect failed');
      exit(1);
    }
    final chip = (chipResult as Success<EspChipInfo>).value;
    stdout.writeln('Chip: ${chip.family.name} (${chip.description})');

    // 2. SPI_ATTACH
    stdout.writeln('\n--- SPI_ATTACH ---');
    await transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.spiAttach, data: Uint8List(8)),
    );
    stdout.writeln('spiAttach done');

    // 3. Try one SPI READ chunk at 0x8000
    stdout.writeln('\n--- SPI READ 0x8000 (32 bytes) ---');
    const base = 0x3FF42000; // ESP32 SPI1
    const spiCmdReg = base + 0x00;
    const spiAddrReg = base + 0x04;
    const spiUsrReg = base + 0x1C;
    const spiUsr1Reg = base + 0x20;
    const spiUsr2Reg = base + 0x24;
    const spiMosiDlenReg = base + 0x28;
    const spiMisoDlenReg = base + 0x2C;
    const spiW0Reg = base + 0x80;

    // Read current register values
    stdout.writeln('Reading USR regs...');
    final oldUsr = await readReg(transport, spiUsrReg, 'SPI_USR');
    final oldUsr2 = await readReg(transport, spiUsr2Reg, 'SPI_USR2');
    final oldUsr1 = await readReg(transport, spiUsr1Reg, 'SPI_USR1');
    stdout.writeln(
      'oldUsr=0x${oldUsr.toRadixString(16)} oldUsr1=0x${oldUsr1.toRadixString(16)} oldUsr2=0x${oldUsr2.toRadixString(16)}',
    );

    // Set MOSI_DLEN=0, MISO_DLEN=255 (32 bytes)
    stdout.writeln('Setting DLEN...');
    await writeReg(transport, spiMisoDlenReg, 255, 'MISO_DLEN');
    await writeReg(transport, spiMosiDlenReg, 0, 'MOSI_DLEN');

    // USR1: addr_bitlen=23 (24-bit address)
    const addrBitlen = 23;
    const spiUsrAddrLenShift = 26;
    final newUsr1 = (oldUsr1 & 0x03FFFFFF) | (addrBitlen << spiUsrAddrLenShift);
    stdout.writeln('Setting USR1=0x${newUsr1.toRadixString(16)}...');
    await writeReg(transport, spiUsr1Reg, newUsr1, 'SPI_USR1');

    // USR: command(31) | addr(26) | miso(28)
    const spiUsrCommand = 1 << 31;
    const spiUsrAddr = 1 << 26;
    const spiUsrMiso = 1 << 28;
    const usrVal = spiUsrCommand | spiUsrAddr | spiUsrMiso;
    stdout.writeln('Setting USR=0x${usrVal.toRadixString(16)}...');
    await writeReg(transport, spiUsrReg, usrVal, 'SPI_USR');

    // USR2: 8-bit READ command 0x03
    const spiUsr2CmdLenShift = 28;
    const usr2Val = (7 << spiUsr2CmdLenShift) | 0x03;
    stdout.writeln('Setting USR2=0x${usr2Val.toRadixString(16)}...');
    await writeReg(transport, spiUsr2Reg, usr2Val, 'SPI_USR2');

    // SPI_ADDR: flash address 0x8000 << 8
    const flashAddr = 0x8000;
    const addrVal = flashAddr << 8;
    stdout.writeln('Setting ADDR=0x${addrVal.toRadixString(16)}...');
    await writeReg(transport, spiAddrReg, addrVal, 'SPI_ADDR');

    // Trigger SPI transaction
    stdout.writeln('Triggering SPI transaction...');
    const spiCmdUsr = 1 << 18;
    await writeReg(transport, spiCmdReg, spiCmdUsr, 'SPI_CMD(trigger)');
    stdout.writeln('Triggered!');

    // Poll until done
    stdout.writeln('Polling CMD reg for completion...');
    for (var i = 0; i < 16; i++) {
      final cmdVal = await readReg(transport, spiCmdReg, 'SPI_CMD(poll)');
      stdout.writeln(
        '  Poll $i: CMD=0x${cmdVal.toRadixString(16)} bit18=${(cmdVal >> 18) & 1}',
      );
      if ((cmdVal & spiCmdUsr) == 0) {
        stdout.writeln('Transaction complete!');
        // Read W0 register (first 4 bytes)
        for (var w = 0; w < 8; w++) {
          final wVal = await readReg(transport, spiW0Reg + w * 4, 'W$w');
          final bytes = [
            wVal & 0xFF,
            (wVal >> 8) & 0xFF,
            (wVal >> 16) & 0xFF,
            (wVal >> 24) & 0xFF,
          ];
          final hex = bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' ');
          stdout.writeln(
            '  W$w = 0x${wVal.toRadixString(16).padLeft(8, '0')} [$hex]',
          );
        }
        break;
      }
    }

    // Restore
    await writeReg(transport, spiUsr1Reg, oldUsr1, 'restore USR1');
    await writeReg(transport, spiUsrReg, oldUsr, 'restore USR');
    await writeReg(transport, spiUsr2Reg, oldUsr2, 'restore USR2');
    stdout.writeln('\nDone!');
  } catch (e, st) {
    stderr.writeln('Error: $e\n$st');
    exit(1);
  } finally {
    await transport.close();
  }
}

Future<int> readReg(
  EspTransportInterface transport,
  int addr,
  String name,
) async {
  final payload = Uint8List(4);
  ByteData.sublistView(payload).setUint32(0, addr, Endian.little);
  final r = await transport.sendCommand(
    EspCommand(opcode: EspCommandOpcode.readReg, data: payload),
  );
  if (!r.isSuccess) throw Exception('readReg $name failed');
  stdout.writeln(
    '  readReg $name(0x${addr.toRadixString(16)})=0x${r.value.toRadixString(16)}',
  );
  return r.value;
}

Future<void> writeReg(
  EspTransportInterface transport,
  int addr,
  int value,
  String name,
) async {
  final payload = Uint8List(16);
  final d = ByteData.sublistView(payload);
  d.setUint32(0, addr, Endian.little);
  d.setUint32(4, value, Endian.little);
  d.setUint32(8, 0xFFFFFFFF, Endian.little);
  d.setUint32(12, 0, Endian.little);
  final r = await transport.sendCommand(
    EspCommand(opcode: EspCommandOpcode.writeReg, data: payload),
  );
  if (!r.isSuccess) {
    throw Exception('writeReg $name failed: status=${r.status}');
  }
  stdout.writeln(
    '  writeReg $name(0x${addr.toRadixString(16)})=0x${value.toRadixString(16)} ok',
  );
}
