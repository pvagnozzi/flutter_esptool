// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Holds the parsed response from the ESP32 GET_SECURITY_INFO command (opcode 0x14).
///
/// The ROM bootloader returns a 20-byte payload:
///   [0..3]   flags           (uint32 LE) — reserved / future use
///   [4]      flash_crypt_cnt (uint8)     — odd popcount of bits [2:0] → encryption active
///   [5..11]  key_purposes    (7 bytes)   — eFuse key purpose for blocks 1–7
///   [12..15] chip_id         (uint32 LE)
///   [16..19] api_version     (uint32 LE) — ROM API version
///
/// Flash encryption is active when the number of set bits in
/// (flash_crypt_cnt & 0x07) is odd (matches SPI_BOOT_CRYPT_CNT eFuse logic).
class EspSecurityInfo {
  /// Raw flags field (reserved / future use).
  final int flags;

  /// Raw flash_crypt_cnt byte from the GET_SECURITY_INFO response.
  final int flashCryptCnt;

  /// Raw key purpose bytes for eFuse key blocks 1–7.
  final List<int> keyPurposes;

  /// Chip ID as reported by the ROM.
  final int chipId;

  /// ROM API version.
  final int apiVersion;

  const EspSecurityInfo({
    required this.flags,
    required this.flashCryptCnt,
    required this.keyPurposes,
    required this.chipId,
    required this.apiVersion,
  });

  /// True when flash encryption is currently active on this device.
  ///
  /// Flash encryption is enabled when the number of set bits in the lower 3
  /// bits of [flashCryptCnt] (the SPI_BOOT_CRYPT_CNT eFuse field) is **odd**.
  bool get flashEncryptionEnabled {
    final cnt = flashCryptCnt & 0x07;
    var bits = 0;
    for (var i = 0; i < 3; i++) {
      if ((cnt >> i) & 1 == 1) bits++;
    }
    return bits.isOdd;
  }

  /// True when Secure Boot V2 is enabled on this device.
  ///
  /// Bit 0 of [flags] is set by the ROM when secure boot is active.
  /// (ESP-IDF `esp_rom_get_security_info()` sets flag bit 0 = ABS_DONE_0.)
  bool get secureBootEnabled => (flags & 0x01) != 0;

  @override
  String toString() => 'EspSecurityInfo('
      'flashEncryptionEnabled=$flashEncryptionEnabled, '
      'secureBootEnabled=$secureBootEnabled, '
      'flashCryptCnt=0x${flashCryptCnt.toRadixString(16)}, '
      'chipId=0x${chipId.toRadixString(16)}, '
      'apiVersion=$apiVersion'
      ')';
}
