// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspCircuitBreaker', () {
    late EspCircuitBreaker breaker;

    setUp(() {
      breaker = EspCircuitBreaker(
        failureThreshold: 3,
        successThreshold: 2,
        resetTimeout: const Duration(seconds: 60),
        tripOn: {EspErrorType.timeout, EspErrorType.partialPacket},
      );
    });

    // ── Initial state ────────────────────────────────────────────────────────

    test('starts in closed state', () {
      expect(breaker.state, EspCircuitBreakerState.closed);
      expect(breaker.failureCount, 0);
      expect(breaker.successCount, 0);
      expect(breaker.allowsRequest, isTrue);
      expect(breaker.timeUntilHalfOpen, isNull);
    });

    // ── closed → open ────────────────────────────────────────────────────────

    test('trips to open after failureThreshold consecutive failures', () {
      breaker.recordFailure(EspErrorType.timeout);
      expect(breaker.state, EspCircuitBreakerState.closed);
      breaker.recordFailure(EspErrorType.timeout);
      expect(breaker.state, EspCircuitBreakerState.closed);
      breaker.recordFailure(EspErrorType.timeout); // 3rd → open
      expect(breaker.state, EspCircuitBreakerState.open);
    });

    test('does not trip on non-trip errors', () {
      for (var i = 0; i < 10; i++) {
        breaker.recordFailure(EspErrorType.syncFailed);
      }
      expect(breaker.state, EspCircuitBreakerState.closed);
    });

    test('resets failure counter on success while closed', () {
      breaker.recordFailure(EspErrorType.timeout);
      breaker.recordFailure(EspErrorType.timeout);
      breaker.recordSuccess();
      expect(breaker.failureCount, 0);

      // Now threshold is 3 again; previous 2 failures are wiped.
      breaker.recordFailure(EspErrorType.timeout);
      breaker.recordFailure(EspErrorType.timeout);
      expect(breaker.state, EspCircuitBreakerState.closed);
    });

    // ── open state ───────────────────────────────────────────────────────────

    test('open state blocks requests', () {
      // Trip the breaker.
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure(EspErrorType.timeout);
      }
      expect(breaker.allowsRequest, isFalse);
    });

    test('timeUntilHalfOpen is non-null and positive when open', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure(EspErrorType.timeout);
      }
      expect(breaker.state, EspCircuitBreakerState.open);
      final remaining = breaker.timeUntilHalfOpen;
      expect(remaining, isNotNull);
      expect(remaining!.inSeconds, greaterThan(0));
    });

    // ── open → halfOpen ──────────────────────────────────────────────────────

    test('transitions to halfOpen after resetTimeout', () {
      final fastBreaker = EspCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 10),
        tripOn: {EspErrorType.timeout},
      );
      fastBreaker.recordFailure(EspErrorType.timeout);
      expect(fastBreaker.state, EspCircuitBreakerState.open);

      // Wait past the reset timeout.
      // allowsRequest checks elapsed time and auto-transitions.
      Future<void>.delayed(const Duration(milliseconds: 15)).then((_) {
        expect(fastBreaker.allowsRequest, isTrue);
        expect(fastBreaker.state, EspCircuitBreakerState.halfOpen);
      });
    });

    test('allowsRequest auto-transitions open→halfOpen when timeout expired',
        () async {
      final fastBreaker = EspCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 1),
        tripOn: {EspErrorType.timeout},
      );
      fastBreaker.recordFailure(EspErrorType.timeout);
      expect(fastBreaker.state, EspCircuitBreakerState.open);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fastBreaker.allowsRequest, isTrue);
      expect(fastBreaker.state, EspCircuitBreakerState.halfOpen);
    });

    // ── halfOpen → closed ────────────────────────────────────────────────────

    test('closes after successThreshold successes in halfOpen', () async {
      final fastBreaker = EspCircuitBreaker(
        failureThreshold: 1,
        successThreshold: 2,
        resetTimeout: const Duration(milliseconds: 1),
        tripOn: {EspErrorType.timeout},
      );
      fastBreaker.recordFailure(EspErrorType.timeout);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Trigger halfOpen transition.
      expect(fastBreaker.allowsRequest, isTrue);

      fastBreaker.recordSuccess();
      expect(fastBreaker.state, EspCircuitBreakerState.halfOpen);

      fastBreaker.recordSuccess(); // 2nd success → closed
      expect(fastBreaker.state, EspCircuitBreakerState.closed);
      expect(fastBreaker.failureCount, 0);
      expect(fastBreaker.successCount, 0);
    });

    // ── halfOpen → open ──────────────────────────────────────────────────────

    test('re-trips to open on any failure while halfOpen', () async {
      final fastBreaker = EspCircuitBreaker(
        failureThreshold: 1,
        resetTimeout: const Duration(milliseconds: 1),
        tripOn: {EspErrorType.timeout},
      );
      fastBreaker.recordFailure(EspErrorType.timeout);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fastBreaker.allowsRequest, isTrue); // → halfOpen
      expect(fastBreaker.state, EspCircuitBreakerState.halfOpen);

      fastBreaker.recordFailure(EspErrorType.timeout); // → open
      expect(fastBreaker.state, EspCircuitBreakerState.open);
    });

    // ── manual reset ─────────────────────────────────────────────────────────

    test('reset() moves any state back to closed', () {
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure(EspErrorType.timeout);
      }
      expect(breaker.state, EspCircuitBreakerState.open);
      breaker.reset();
      expect(breaker.state, EspCircuitBreakerState.closed);
      expect(breaker.failureCount, 0);
      expect(breaker.timeUntilHalfOpen, isNull);
    });

    // ── mixed error types ────────────────────────────────────────────────────

    test('counts mixed trip errors towards the threshold', () {
      breaker.recordFailure(EspErrorType.timeout);
      breaker.recordFailure(EspErrorType.partialPacket);
      breaker.recordFailure(EspErrorType.timeout);
      expect(breaker.state, EspCircuitBreakerState.open);
    });

    test('ignores non-trip errors even after many failures', () {
      for (var i = 0; i < 100; i++) {
        breaker.recordFailure(EspErrorType.invalidChip);
        breaker.recordFailure(EspErrorType.flashWriteFailed);
      }
      expect(breaker.state, EspCircuitBreakerState.closed);
    });
  });
}
