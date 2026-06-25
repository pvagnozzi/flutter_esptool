// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:math';

import 'package:flutter_esptool/src/models/esp_error.dart';

/// Configures retry behaviour for [EspResilientTransport.sendCommand].
///
/// Delays grow exponentially up to [maxDelay] with optional ±25 % jitter.
/// Only errors listed in [retryOn] qualify for a retry; all others propagate
/// immediately.
///
/// ```dart
/// // 3 total attempts, 100 ms → 200 ms backoff, transient errors only:
/// const policy = EspRetryPolicy(maxAttempts: 3);
///
/// // Never retry (pass-through):
/// EspRetryPolicy.noRetry
/// ```
class EspRetryPolicy {
  /// Creates an [EspRetryPolicy].
  const EspRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 100),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 2),
    this.jitter = true,
    this.retryOn = const {
      EspErrorType.timeout,
      EspErrorType.partialPacket,
    },
  });

  /// Maximum number of total attempts (1 = no retry, 3 = initial + 2 retries).
  final int maxAttempts;

  /// Base delay before the first retry.
  final Duration initialDelay;

  /// Exponential growth factor applied to [initialDelay] on each retry.
  final double backoffFactor;

  /// Hard cap on per-retry delay after applying [backoffFactor].
  final Duration maxDelay;

  /// When `true`, a ±25 % random jitter is added to prevent thundering herd.
  final bool jitter;

  /// Error types that qualify for a retry; all other types propagate
  /// immediately without retrying.
  final Set<EspErrorType> retryOn;

  /// A policy that never retries (single attempt, no delay).
  static const EspRetryPolicy noRetry = EspRetryPolicy(maxAttempts: 1);

  /// Returns `true` when [type] should trigger another attempt.
  bool shouldRetry(EspErrorType type) => retryOn.contains(type);

  /// Computes the delay before retry number [attempt] (0-indexed,
  /// first retry = 0, second retry = 1, …).
  Duration delayFor(int attempt) {
    final rawMs =
        initialDelay.inMilliseconds * pow(backoffFactor, attempt).toDouble();
    final cappedMs = rawMs.clamp(0.0, maxDelay.inMilliseconds.toDouble());
    if (!jitter) return Duration(milliseconds: cappedMs.round());
    // Apply a [0.75, 1.25) factor for ±25 % jitter.
    final factor = 0.75 + Random().nextDouble() * 0.5;
    return Duration(milliseconds: (cappedMs * factor).round());
  }
}
