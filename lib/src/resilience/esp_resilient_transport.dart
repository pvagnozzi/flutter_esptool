// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/resilience/esp_circuit_breaker.dart';
import 'package:flutter_esptool/src/resilience/esp_retry_policy.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';

/// A decorating [EspTransportInterface] that adds retry and circuit-breaker
/// resilience around [sendCommand] while delegating every other call unchanged.
///
/// ## How it works
///
/// 1. **Circuit breaker** — if [circuitBreaker] is set and its state is *open*,
///    [sendCommand] throws [EspErrorType.circuitBreakerOpen] immediately without
///    touching the wire.
/// 2. **Retry** — on a transient error (listed in [EspRetryPolicy.retryOn]) the
///    command is retried up to [EspRetryPolicy.maxAttempts] times with
///    exponential back-off.  Non-retryable errors propagate on the first
///    failure.
/// 3. **Circuit breaker feedback** — every success/failure is reported to the
///    circuit breaker so it can transition between states.
///
/// ## Usage
///
/// ```dart
/// // Wrap the real transport:
/// final transport = EspResilientTransport(
///   EspTransport(),
///   retryPolicy: const EspRetryPolicy(maxAttempts: 3),
///   circuitBreaker: EspCircuitBreaker(failureThreshold: 5),
/// );
///
/// // Use exactly like a plain EspTransport:
/// final connection = ConnectionService(transport);
/// final detection  = ChipDetectionService(transport);
///
/// // Inspect the breaker at any time:
/// print(transport.circuitBreaker?.state);
/// ```
class EspResilientTransport implements EspTransportInterface {
  /// Creates an [EspResilientTransport] wrapping [inner].
  ///
  /// [retryPolicy] defaults to [EspRetryPolicy] (3 attempts, 100 ms backoff).
  /// [circuitBreaker] is optional — omit it to disable the breaker.
  EspResilientTransport(
    this._inner, {
    EspRetryPolicy? retryPolicy,
    EspCircuitBreaker? circuitBreaker,
  })  : _retryPolicy = retryPolicy ?? const EspRetryPolicy(),
        _circuitBreaker = circuitBreaker;

  final EspTransportInterface _inner;
  final EspRetryPolicy _retryPolicy;
  final EspCircuitBreaker? _circuitBreaker;

  /// The optional circuit breaker guarding this transport.
  EspCircuitBreaker? get circuitBreaker => _circuitBreaker;

  /// The active retry policy.
  EspRetryPolicy get retryPolicy => _retryPolicy;

  // ── Delegation ─────────────────────────────────────────────────────────────

  @override
  bool get isOpen => _inner.isOpen;

  @override
  Future<void> open(EspConfig config) => _inner.open(config);

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> resetToBootloader() => _inner.resetToBootloader();

  @override
  Future<void> changeBaud(int newBaud) => _inner.changeBaud(newBaud);

  // ── Resilient sendCommand ───────────────────────────────────────────────────

  @override
  Future<EspResponse> sendCommand(
    EspCommand command, {
    Duration? timeout,
  }) async {
    final breaker = _circuitBreaker;

    // 1. Fast-fail if the circuit is open.
    if (breaker != null && !breaker.allowsRequest) {
      final remainingS = breaker.timeUntilHalfOpen?.inSeconds ?? 0;
      throw EspError(
        type: EspErrorType.circuitBreakerOpen,
        message: 'Circuit breaker is OPEN — too many recent failures. '
            'Probing resumes in ${remainingS}s.',
      );
    }

    // 2. Attempt the command with retries.
    EspError? lastError;
    for (var attempt = 0; attempt < _retryPolicy.maxAttempts; attempt++) {
      // Wait before each retry (not before the first attempt).
      if (attempt > 0) {
        await Future<void>.delayed(_retryPolicy.delayFor(attempt - 1));
      }
      try {
        final response = await _inner.sendCommand(command, timeout: timeout);
        // 3a. Record success.
        breaker?.recordSuccess();
        return response;
      } on EspError catch (error) {
        lastError = error;
        // 3b. Record failure.
        breaker?.recordFailure(error.type);
        // Non-retryable error or last attempt: propagate immediately.
        if (!_retryPolicy.shouldRetry(error.type) ||
            attempt + 1 >= _retryPolicy.maxAttempts) {
          rethrow;
        }
        // Continue to the next attempt after the delay.
      }
    }
    // Unreachable, but satisfies the type-checker.
    throw lastError!;
  }
}
