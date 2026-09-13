// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

/// Reed-Solomon(12) encoder for ESP32-S3 eFuse key blocks.
///
/// ESP32-S3 (and other later ESP32 chips) protect key eFuse blocks with a
/// Reed-Solomon error-correcting code.  When burning a 32-byte key block the
/// host must supply 12 additional RS "check" bytes, written to the eFuse
/// controller's `CHECK_VALUE` registers.  These are computed with the exact
/// same parameters `esptool`/`espefuse` use via the `reedsolo` Python package:
///
///   * symbol size  : 8 bits (GF(2^8))
///   * primitive    : 0x11D  (x^8 + x^4 + x^3 + x^2 + 1)
///   * generator    : 2
///   * fcr          : 0      (first consecutive root exponent)
///   * nsym         : 12     (number of parity symbols)
///
/// Encoding is *systematic*: the 12 parity bytes are appended after the 32
/// data bytes, producing a 44-byte codeword.  This matches
/// `reedsolo.RSCodec(12).encode(data)`.
///
/// Golden reference (validated against espefuse 4.8.1): for the 32-byte input
/// `00 01 02 ... 1f`, the 12 parity bytes are:
///   `a0 4c 47 0d 3f fc b2 03 da e9 f4 13`.
class ReedSolomon12 {
  ReedSolomon12() {
    _initTables();
    _generator = _buildGeneratorPoly(_nsym);
  }

  static const int _prim = 0x11D;
  // Generator element is 2 (alpha); fcr is 0. Both are baked into the
  // exp/log tables and generator-polynomial roots below.
  static const int _fcr = 0;
  static const int _nsym = 12;

  // GF(2^8) exp/log lookup tables (size 512 for exp to avoid modulo).
  final Uint8List _gfExp = Uint8List(512);
  final Uint8List _gfLog = Uint8List(256);
  late final List<int> _generator;

  void _initTables() {
    var x = 1;
    for (var i = 0; i < 255; i++) {
      _gfExp[i] = x;
      _gfLog[x] = i;
      x <<= 1;
      if (x & 0x100 != 0) {
        x ^= _prim;
      }
    }
    // Extend exp table so gfMul can index without a modulo.
    for (var i = 255; i < 512; i++) {
      _gfExp[i] = _gfExp[i - 255];
    }
  }

  int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _gfExp[_gfLog[a] + _gfLog[b]];
  }

  /// Builds the RS generator polynomial for [nsym] parity symbols:
  ///   g(x) = (x - a^fcr)(x - a^(fcr+1)) ... (x - a^(fcr+nsym-1))
  /// Coefficients are returned most-significant first.
  List<int> _buildGeneratorPoly(int nsym) {
    var g = <int>[1];
    for (var i = 0; i < nsym; i++) {
      final root = _gfExp[(_fcr + i) % 255];
      // Multiply g(x) by (x - root)  == (x + root) in GF(2).
      final next = List<int>.filled(g.length + 1, 0);
      for (var j = 0; j < g.length; j++) {
        next[j] ^= g[j]; // g[j] * x
        next[j + 1] ^= _gfMul(g[j], root); // g[j] * root
      }
      g = next;
    }
    return g;
  }

  /// Encodes [data] (systematic), returning `data || parity`.
  ///
  /// [data] may be any length, but for ESP32-S3 key blocks it is always 32
  /// bytes, producing a 44-byte result.
  Uint8List encode(List<int> data) {
    final parity = computeParity(data);
    final out = Uint8List(data.length + parity.length);
    out.setRange(0, data.length, data);
    out.setRange(data.length, out.length, parity);
    return out;
  }

  /// Computes only the [_nsym] parity bytes for [data].
  Uint8List computeParity(List<int> data) {
    // Polynomial long division of (data * x^nsym) by the generator polynomial.
    // The remainder is the parity. Uses a running register of length nsym.
    final parity = Uint8List(_nsym);
    for (final byte in data) {
      final feedback = byte ^ parity[0];
      // Shift register left by one.
      for (var j = 0; j < _nsym - 1; j++) {
        parity[j] = parity[j + 1] ^ _gfMul(_generator[j + 1], feedback);
      }
      parity[_nsym - 1] = _gfMul(_generator[_nsym], feedback);
    }
    return parity;
  }
}
