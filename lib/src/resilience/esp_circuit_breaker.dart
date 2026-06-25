// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_error.dart';

/// Possible states of an [EspCircuitBreaker].
enum EspCircuitBreakerState {
  /// Normal operation — all requests pass through.
  closed,

  /// Too many failures — every request is rejected immediately.
  open,

  /// Recovery probing — a limited number of requests are let through to test
  /// whether the device has recovered.
  halfOpen,
}

/// A circuit breaker that guards the ESP serial connection against cascading
/// failures.
///
/// ## State machine
///
/// ```
///  CLOSED ──[failureThreshold consecutive failures]──► OPEN
///  OPEN   ──[resetTimeout elapsed]────────────────────► HALF-OPEN
///  HALF-OPEN ──[successThreshold consecutive successes]─► CLOSED
///  HALF-OPEN ──[any qualifying failure]────────────────► OPEN
/// ```
///
/// ## Usage
///
/// ```dart
/// final breaker = EspCircuitBreaker(
///   failureThreshold: 5,
///   resetTimeout: const Duration(seconds: 30),
/// );
///
/// final transport = EspResilientTransport(
///   EspTransport(),
///   circuitBreaker: breaker,
/// );
///
/// // Inspect state:
/// print(breaker.state);          // EspCircuitBreakerState.closed
/// print(breaker.failureCount);   // 0
/// ```
class EspCircuitBreaker {
  /// Creates an [EspCircuitBreaker].
  EspCircuitBreaker({
    this.failureThreshold = 5,
    this.successThreshold = 2,
    this.resetTimeout = const Duration(seconds: 30),
    this.tripOn = const {
      EspErrorType.timeout,
      EspErrorType.partialPacket,
      EspErrorType.connectionFailed,
    },
  });

  /// Consecutive failures required to trip from *closed* to *open*.
  final int failureThreshold;

  /// Consecutive successes in *halfOpen* required to close the circuit.
  final int successThreshold;

  /// How long the breaker stays *open* before probing in *halfOpen*.
  final Duration resetTimeout;

  /// Error types that count towards the failure threshold.
  final Set<EspErrorType> tripOn;

  EspCircuitBreakerState _state = EspCircuitBreakerState.closed;
  int _failureCount = 0;
  int _successCount = 0;
  DateTime? _openedAt;

  /// The current breaker state.
  EspCircuitBreakerState get state => _state;

  /// Consecutive failures since the last success or state transition.
  int get failureCount => _failureCount;

  /// Consecutive successes accumulated while in *halfOpen*.
  int get successCount => _successCount;

  /// Remaining time in *open* before the breaker transitions to *halfOpen*,
  /// or `null` when not in the *open* state.
  Duration? get timeUntilHalfOpen {
    if (_state != EspCircuitBreakerState.open || _openedAt == null) {
      return null;
    }
    final remaining = resetTimeout - DateTime.now().difference(_openedAt!);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// `true` when a request may proceed, `false` when the breaker blocks it.
  ///
  /// Calling this method on an *open* breaker whose [resetTimeout] has expired
  /// automatically transitions to *halfOpen* and returns `true`.
  bool get allowsRequest {
    switch (_state) {
      case EspCircuitBreakerState.closed:
        return true;
      case EspCircuitBreakerState.halfOpen:
        return true;
      case EspCircuitBreakerState.open:
        if (DateTime.now().difference(_openedAt!) >= resetTimeout) {
          _transitionTo(EspCircuitBreakerState.halfOpen);
          return true;
        }
        return false;
    }
  }

  /// Records a successful operation outcome.
  void recordSuccess() {
    switch (_state) {
      case EspCircuitBreakerState.closed:
        _failureCount = 0;
      case EspCircuitBreakerState.halfOpen:
        _successCount++;
        if (_successCount >= successThreshold) {
          _transitionTo(EspCircuitBreakerState.closed);
        }
      case EspCircuitBreakerState.open:
        break;
    }
  }

  /// Records a failed operation with error [type].
  ///
  /// Only errors in [tripOn] advance the failure counter or trip the breaker.
  void recordFailure(EspErrorType type) {
    if (!tripOn.contains(type)) return;
    switch (_state) {
      case EspCircuitBreakerState.closed:
        _failureCount++;
        if (_failureCount >= failureThreshold) {
          _transitionTo(EspCircuitBreakerState.open);
        }
      case EspCircuitBreakerState.halfOpen:
        _transitionTo(EspCircuitBreakerState.open);
      case EspCircuitBreakerState.open:
        break;
    }
  }

  /// Manually resets the breaker to the *closed* state.
  void reset() => _transitionTo(EspCircuitBreakerState.closed);

  void _transitionTo(EspCircuitBreakerState next) {
    _state = next;
    switch (next) {
      case EspCircuitBreakerState.closed:
        _failureCount = 0;
        _successCount = 0;
        _openedAt = null;
      case EspCircuitBreakerState.open:
        _openedAt = DateTime.now();
        _successCount = 0;
      case EspCircuitBreakerState.halfOpen:
        _successCount = 0;
    }
  }
}
