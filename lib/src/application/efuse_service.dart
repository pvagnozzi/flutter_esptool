// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/efuse/reed_solomon.dart';
import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';

/// eFuse programming for **ESP32-S3** Secure Boot V2 provisioning.
///
/// ⚠️  Every operation in this service is **irreversible**.  Burning an eFuse
/// permanently sets bits that can never be cleared.  A wrong key digest or an
/// accidental `SECURE_BOOT_EN` burn will **permanently brick** the device.
/// The caller is responsible for confirming the operator's intent and for
/// verifying the digest against the signing public key before calling
/// [burnSecureBootKeyDigest] / [enableSecureBoot].
///
/// The register sequence mirrors `espefuse.py` (esptool 4.8.1) exactly and
/// uses only the `WRITE_REG` (0x09) / `READ_REG` (0x0A) ROM opcodes, so it
/// works from the ROM bootloader without the flasher stub.
///
/// Only ESP32-S3 is supported.  Do **not** use this on plain ESP32
/// (Secure Boot V1) or other families — the register map and coding scheme
/// differ.
class EfuseService {
  /// Creates an [EfuseService] bound to [transport].
  EfuseService({required EspTransportInterface transport})
      : _transport = transport;

  final EspTransportInterface _transport;
  final ReedSolomon12 _rs = ReedSolomon12();

  // ── ESP32-S3 eFuse controller registers (DR_REG_EFUSE_BASE = 0x60007000) ──
  static const int _base = 0x60007000;
  static const int _pgmData0Reg = _base + 0x000; // PGM_DATA0..7  (32 bytes)
  static const int _checkValue0Reg = _base + 0x020; // CHECK_VALUE0..2 (12 B)
  static const int _confReg = _base + 0x1CC;
  static const int _statusReg = _base + 0x1D0;
  static const int _cmdReg = _base + 0x1D4;

  static const int _writeOpCode = 0x5A5A;
  static const int _readOpCode = 0x5AA5;
  static const int _pgmCmd = 0x2;
  static const int _readCmd = 0x1;

  // ── Block indices / field layout ──────────────────────────────────────────
  /// BLOCK_KEY0 (BLOCK4) holds the flash-encryption (XTS-AES-128) key.
  /// BLOCK_KEY1 (BLOCK5) holds the Secure Boot V2 key digest.
  static const int blockKey0 = 4;
  static const int blockKey1 = 5;
  static const int _block0 = 0;

  /// KEY_PURPOSE value for SECURE_BOOT_DIGEST0 (ESP32-S3).
  static const int keyPurposeSecureBootDigest0 = 9;

  /// KEY_PURPOSE value for XTS_AES_128_KEY / flash encryption (ESP32-S3).
  static const int keyPurposeXtsAes128 = 4;

  // BLOCK0 field bit positions (word index within block + bit offset).
  static const int _wrDisWord = 0; // WR_DIS is BLOCK0 word0, 32 bits.
  static const int _wrDisKeyPurpose0Bit = 8;
  static const int _wrDisKeyPurpose1Bit = 9;
  static const int _wrDisBlockKey0Bit = 23;
  static const int _wrDisBlockKey1Bit = 24;

  // RD_DIS is BLOCK0 word1 (offset 32), 7 bits; bit N read-protects BLOCK_KEY(N).
  static const int _rdDisWord = 1;
  static const int _rdDisBlockKey0Bit = 0;

  static const int _keyPurpose0Word = 2;
  static const int _keyPurpose0Shift = 24; // pos 24, len 4
  static const int _keyPurpose1Word = 2;
  static const int _keyPurpose1Shift = 28; // pos 28, len 4
  static const int _secureBootEnWord = 3;
  static const int _secureBootEnBit = 20; // pos 20, len 1

  // ---------------------------------------------------------------------------
  // Pure helpers (unit-testable without a device)
  // ---------------------------------------------------------------------------

  /// Computes the 11 little-endian 32-bit words that must be written to the
  /// PGM_DATA0..7 + CHECK_VALUE0..2 registers to burn [digest] into a
  /// Reed-Solomon-coded key block.
  ///
  /// [digest] must be exactly 32 bytes.  The first 8 words are the key data;
  /// the last 3 are the RS(12) check words.
  static List<int> keyBlockWords(Uint8List digest, {ReedSolomon12? rs}) {
    if (digest.length != 32) {
      throw ArgumentError('Key digest must be 32 bytes, got ${digest.length}');
    }
    final encoded = (rs ?? ReedSolomon12()).encode(digest); // 44 bytes
    final bd = ByteData.sublistView(encoded);
    return List<int>.generate(11, (i) => bd.getUint32(i * 4, Endian.little));
  }

  /// Computes the 8 BLOCK0 words needed to finalise the flash-encryption key:
  /// KEY_PURPOSE_0 = XTS_AES_128_KEY, WR_DIS for the purpose + key block, and
  /// (when [readProtect]) RD_DIS for BLOCK_KEY0.
  ///
  /// Exposed for unit testing; used by [lockFlashEncryptionKey].
  static List<int> flashEncryptionLockBlock0({bool readProtect = true}) {
    final block0 = List<int>.filled(8, 0);
    block0[_keyPurpose0Word] = keyPurposeXtsAes128 << _keyPurpose0Shift;
    block0[_wrDisWord] =
        (1 << _wrDisKeyPurpose0Bit) | (1 << _wrDisBlockKey0Bit);
    if (readProtect) {
      block0[_rdDisWord] = 1 << _rdDisBlockKey0Bit;
    }
    return block0;
  }

  // ---------------------------------------------------------------------------
  // High-level Secure Boot V2 operations
  // ---------------------------------------------------------------------------

  /// Burns the RSA-3072 public-key [digest] (32 bytes) into BLOCK_KEY1 and
  /// sets KEY_PURPOSE_1 = SECURE_BOOT_DIGEST0, write-protecting both.
  ///
  /// This does **not** set `SECURE_BOOT_EN`; call [enableSecureBoot] separately
  /// (or let the firmware self-enable on first boot).  The digest is public and
  /// is intentionally **not** read-protected.
  Future<Result<void>> burnSecureBootKeyDigest(Uint8List digest) async {
    try {
      if (digest.length != 32) {
        return Failure<void>(
          EspError(
            type: EspErrorType.unsupportedOperation,
            message: 'Secure Boot key digest must be 32 bytes, '
                'got ${digest.length}',
          ),
        );
      }

      // 1. Burn the key digest + RS check words into BLOCK_KEY1.
      final words = keyBlockWords(digest, rs: _rs);
      await _programBlock(blockKey1, words);

      // 2. Set KEY_PURPOSE_1 = SECURE_BOOT_DIGEST0 and write-protect the
      //    purpose (WR_DIS bit 9) + the key block (WR_DIS bit 24), matching
      //    espefuse burn_key. The digest is NOT read-protected.
      final block0 = List<int>.filled(8, 0);
      block0[_keyPurpose1Word] =
          keyPurposeSecureBootDigest0 << _keyPurpose1Shift;
      block0[_wrDisWord] =
          (1 << _wrDisKeyPurpose1Bit) | (1 << _wrDisBlockKey1Bit);
      await _programBlock(_block0, block0);

      return const Success<void>(null);
    } catch (error, stackTrace) {
      return Failure<void>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'burnSecureBootKeyDigest failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Permanently enables Secure Boot V2 by burning the `SECURE_BOOT_EN` eFuse
  /// bit and write-protecting it.
  ///
  /// ⚠️  After this the ROM will refuse to boot any bootloader whose signature
  /// does not match the digest in BLOCK_KEY1.  Ensure [burnSecureBootKeyDigest]
  /// succeeded and the signed bootloader is flashed **first**.
  Future<Result<void>> enableSecureBoot() async {
    try {
      final block0 = List<int>.filled(8, 0);
      block0[_secureBootEnWord] = 1 << _secureBootEnBit;
      await _programBlock(_block0, block0);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return Failure<void>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'enableSecureBoot failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Reads the 32-byte Secure Boot key digest currently stored in BLOCK_KEY1.
  ///
  /// Returns all-zero bytes if the block has not been burned yet.
  Future<Result<Uint8List>> readSecureBootKeyDigest() async {
    try {
      // BLOCK_KEY1 read registers: RD base for block 5 = 0x60007000 + 0x0BC.
      const rdBase = _base + 0x0BC;
      final out = Uint8List(32);
      final bd = ByteData.sublistView(out);
      for (var i = 0; i < 8; i++) {
        final word = await _readReg(rdBase + i * 4);
        bd.setUint32(i * 4, word, Endian.little);
      }
      return Success<Uint8List>(out);
    } catch (error, stackTrace) {
      return Failure<Uint8List>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'readSecureBootKeyDigest failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // High-level Flash Encryption (XTS-AES-128) operations
  // ---------------------------------------------------------------------------

  /// Burns the 32-byte flash-encryption [key] into BLOCK_KEY0 **without**
  /// setting the key purpose or any protection bits.
  ///
  /// This is deliberately separated from [lockFlashEncryptionKey] so the caller
  /// can read the block back with [readFlashEncryptionKey] and verify the write
  /// **before** the block is read-protected (after read-protection the key can
  /// never be read again).  Call [lockFlashEncryptionKey] once verified.
  Future<Result<void>> burnFlashEncryptionKeyData(Uint8List key) async {
    try {
      if (key.length != 32) {
        return Failure<void>(
          EspError(
            type: EspErrorType.unsupportedOperation,
            message: 'Flash encryption key must be 32 bytes, got ${key.length}',
          ),
        );
      }
      final words = keyBlockWords(key, rs: _rs);
      await _programBlock(blockKey0, words);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return Failure<void>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'burnFlashEncryptionKeyData failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Reads the 32-byte key currently stored in BLOCK_KEY0.
  ///
  /// Returns all-zero bytes if the block has not been burned yet, and is only
  /// meaningful **before** the block is read-protected via
  /// [lockFlashEncryptionKey].
  Future<Result<Uint8List>> readFlashEncryptionKey() async {
    try {
      // BLOCK_KEY0 read registers: RD base for block 4 = 0x60007000 + 0x09C.
      const rdBase = _base + 0x09C;
      final out = Uint8List(32);
      final bd = ByteData.sublistView(out);
      for (var i = 0; i < 8; i++) {
        final word = await _readReg(rdBase + i * 4);
        bd.setUint32(i * 4, word, Endian.little);
      }
      return Success<Uint8List>(out);
    } catch (error, stackTrace) {
      return Failure<Uint8List>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'readFlashEncryptionKey failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Finalises the flash-encryption key in BLOCK_KEY0: sets
  /// KEY_PURPOSE_0 = XTS_AES_128_KEY, write-protects the purpose + key block,
  /// and (when [readProtect] is true) read-protects the key so it can never be
  /// read back over USB/JTAG.
  ///
  /// Call this **after** [burnFlashEncryptionKeyData] has been verified with
  /// [readFlashEncryptionKey].
  Future<Result<void>> lockFlashEncryptionKey({bool readProtect = true}) async {
    try {
      final block0 = flashEncryptionLockBlock0(readProtect: readProtect);
      await _programBlock(_block0, block0);
      return const Success<void>(null);
    } catch (error, stackTrace) {
      return Failure<void>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'lockFlashEncryptionKey failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Provisioning-state read-back (for resuming an interrupted flow)
  // ---------------------------------------------------------------------------

  /// BLOCK0 read-register base (RD_WR_DIS_REG). word0=WR_DIS, word1=RD_DIS,
  /// word2={SPI_BOOT_CRYPT_CNT@18, KEY_PURPOSE_0@24, KEY_PURPOSE_1@28},
  /// word3={SECURE_BOOT_EN@20}.
  static const int _rdBlock0Base = _base + 0x02C;

  /// Reads the provisioning-relevant BLOCK0 eFuse state so a caller can tell
  /// which secure-provisioning steps have already been completed and skip them
  /// on a resumed run. Purely a read; burns nothing.
  Future<Result<EfuseProvisioningState>> readProvisioningState() async {
    try {
      // Refresh the controller's shadow registers before reading.
      await _triggerEfuseRead();
      final w0 = await _readReg(_rdBlock0Base + 0); // WR_DIS
      final w1 = await _readReg(_rdBlock0Base + 4); // RD_DIS
      final w2 = await _readReg(_rdBlock0Base + 8); // crypt_cnt + key purposes
      final w3 = await _readReg(_rdBlock0Base + 12); // SECURE_BOOT_EN
      return Success<EfuseProvisioningState>(
        EfuseProvisioningState(
          wrDis: w0,
          rdDis: w1 & 0x7F,
          keyPurpose0: (w2 >> 24) & 0xF,
          keyPurpose1: (w2 >> 28) & 0xF,
          spiBootCryptCnt: (w2 >> 18) & 0x7,
          secureBootEn: ((w3 >> 20) & 1) == 1,
        ),
      );
    } catch (error, stackTrace) {
      return Failure<EfuseProvisioningState>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: 'readProvisioningState failed: $error',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Low-level eFuse controller programming
  // ---------------------------------------------------------------------------

  /// Programs a single eFuse [block] with [words] (block-word aligned).
  ///
  /// For RS blocks (all blocks except BLOCK0) [words] must contain 11 entries
  /// (8 data + 3 RS check).  For BLOCK0 [words] contains up to 8 entries.
  /// Mirrors espefuse: setup → write PGM regs → CONF=WRITE → CMD=PGM|(blk<<2)
  /// → wait idle → clear → read-back.
  Future<void> _programBlock(int block, List<int> words) async {
    await _waitEfuseIdle();

    // Clear the 8 PGM_DATA registers first.
    for (var i = 0; i < 8; i++) {
      await _writeReg(_pgmData0Reg + i * 4, 0);
    }

    // Write data words (first 8) to PGM_DATA0..7.
    final dataWordCount = words.length > 8 ? 8 : words.length;
    for (var i = 0; i < dataWordCount; i++) {
      await _writeReg(_pgmData0Reg + i * 4, words[i]);
    }
    // Write RS check words (words 8..10) to CHECK_VALUE0..2.
    for (var i = 8; i < words.length; i++) {
      await _writeReg(_checkValue0Reg + (i - 8) * 4, words[i]);
    }

    // Trigger the program command.
    await _writeReg(_confReg, _writeOpCode);
    await _writeReg(_cmdReg, _pgmCmd | (block << 2));
    await _waitEfuseIdle();

    // Clear PGM registers and issue a read so the controller reloads shadow
    // registers (matches espefuse efuse_program → clear → efuse_read).
    for (var i = 0; i < 8; i++) {
      await _writeReg(_pgmData0Reg + i * 4, 0);
    }
    await _triggerEfuseRead();
  }

  Future<void> _triggerEfuseRead() async {
    await _waitEfuseIdle();
    await _writeReg(_confReg, _readOpCode);
    await _writeReg(_cmdReg, _readCmd);
    await _waitEfuseIdle();
  }

  /// Polls the eFuse controller until no PGM/READ command is pending.
  Future<void> _waitEfuseIdle() async {
    const pending = _pgmCmd | _readCmd;
    for (var attempt = 0; attempt < 100; attempt++) {
      final cmd = await _readReg(_cmdReg);
      if (cmd & pending == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // STATUS register available for diagnostics if the controller stalls.
    final status = await _readReg(_statusReg);
    throw EspError(
      type: EspErrorType.timeout,
      message: 'eFuse controller did not go idle '
          '(STATUS=0x${status.toRadixString(16)})',
    );
  }

  Future<int> _readReg(int address) async {
    final payload = Uint8List(4);
    ByteData.sublistView(payload).setUint32(0, address, Endian.little);
    final resp = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.readReg, data: payload),
      timeout: const Duration(seconds: 3),
    );
    if (!resp.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'readReg(0x${address.toRadixString(16)}) failed: '
            'status=${resp.status} error=${resp.error}',
      );
    }
    return resp.value;
  }

  Future<void> _writeReg(int address, int value) async {
    final payload = Uint8List(16);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, address, Endian.little);
    bd.setUint32(4, value, Endian.little);
    bd.setUint32(8, 0xFFFFFFFF, Endian.little); // mask: all bits
    bd.setUint32(12, 0, Endian.little); // delay_us
    final resp = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.writeReg, data: payload),
      timeout: const Duration(seconds: 3),
    );
    if (!resp.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'writeReg(0x${address.toRadixString(16)}, '
            '0x${value.toRadixString(16)}) failed: '
            'status=${resp.status} error=${resp.error}',
      );
    }
  }
}

/// Snapshot of the provisioning-relevant ESP32-S3 BLOCK0 eFuse state.
///
/// Used to resume an interrupted Secure Boot + Flash Encryption flow by
/// detecting which irreversible steps have already been burned.
class EfuseProvisioningState {
  /// Creates a state snapshot from decoded BLOCK0 fields.
  const EfuseProvisioningState({
    required this.wrDis,
    required this.rdDis,
    required this.keyPurpose0,
    required this.keyPurpose1,
    required this.spiBootCryptCnt,
    required this.secureBootEn,
  });

  /// Raw WR_DIS bitmask (BLOCK0 word0).
  final int wrDis;

  /// RD_DIS bits [0:6] (BLOCK0 word1); bit N read-protects BLOCK_KEY(N).
  final int rdDis;

  /// KEY_PURPOSE_0 (BLOCK_KEY0). 4 = XTS_AES_128_KEY (flash encryption).
  final int keyPurpose0;

  /// KEY_PURPOSE_1 (BLOCK_KEY1). 9 = SECURE_BOOT_DIGEST0.
  final int keyPurpose1;

  /// SPI_BOOT_CRYPT_CNT (3 bits). Flash encryption is active when an odd
  /// number of bits are set.
  final int spiBootCryptCnt;

  /// SECURE_BOOT_EN bit.
  final bool secureBootEn;

  /// True once KEY_PURPOSE_0 has been set to the flash-encryption key purpose.
  bool get flashKeyPurposeSet =>
      keyPurpose0 == EfuseService.keyPurposeXtsAes128;

  /// True when BLOCK_KEY0 is write-protected (WR_DIS bit 23).
  bool get flashKeyWriteProtected => (wrDis >> 23) & 1 == 1;

  /// True when BLOCK_KEY0 is read-protected (RD_DIS bit 0).
  bool get flashKeyReadProtected => rdDis & 1 == 1;

  /// True once the flash-encryption key has been finalised (purpose set +
  /// write-protected) — i.e. steps 1–3 of the flow are complete.
  bool get flashKeyLocked => flashKeyPurposeSet && flashKeyWriteProtected;

  /// True once the Secure Boot V2 digest has been burned into BLOCK_KEY1.
  bool get digestBurned =>
      keyPurpose1 == EfuseService.keyPurposeSecureBootDigest0;

  /// True once SECURE_BOOT_EN is set.
  bool get secureBootEnabled => secureBootEn;

  /// True once the device has actually encrypted its flash (odd CRYPT_CNT).
  /// When set, re-flashing plaintext over download mode must NOT be done.
  bool get flashEncryptionActive {
    final c = spiBootCryptCnt;
    final bits = (c & 1) + ((c >> 1) & 1) + ((c >> 2) & 1);
    return bits.isOdd;
  }

  @override
  String toString() => 'EfuseProvisioningState(keyPurpose0=$keyPurpose0, '
      'keyPurpose1=$keyPurpose1, wrDis=0x${wrDis.toRadixString(16)}, '
      'rdDis=0x${rdDis.toRadixString(16)}, cryptCnt=$spiBootCryptCnt, '
      'secureBootEn=$secureBootEn)';
}
