// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspRetryPolicy', () {
    test('default policy has 3 attempts with transient error set', () {
      const policy = EspRetryPolicy();
      expect(policy.maxAttempts, 3);
      expect(policy.initialDelay, const Duration(milliseconds: 100));
      expect(policy.backoffFactor, 2.0);
      expect(policy.maxDelay, const Duration(seconds: 2));
      expect(policy.jitter, isTrue);
      expect(policy.retryOn,
          containsAll([EspErrorType.timeout, EspErrorType.partialPacket]));
    });

    test('noRetry has maxAttempts == 1', () {
      expect(EspRetryPolicy.noRetry.maxAttempts, 1);
    });

    test('shouldRetry returns true for errors in retryOn', () {
      const policy = EspRetryPolicy(
        retryOn: {EspErrorType.timeout, EspErrorType.partialPacket},
      );
      expect(policy.shouldRetry(EspErrorType.timeout), isTrue);
      expect(policy.shouldRetry(EspErrorType.partialPacket), isTrue);
    });

    test('shouldRetry returns false for errors not in retryOn', () {
      const policy = EspRetryPolicy(retryOn: {EspErrorType.timeout});
      expect(policy.shouldRetry(EspErrorType.syncFailed), isFalse);
      expect(policy.shouldRetry(EspErrorType.flashWriteFailed), isFalse);
      expect(policy.shouldRetry(EspErrorType.circuitBreakerOpen), isFalse);
    });

    test('delayFor without jitter uses pure exponential backoff', () {
      const policy = EspRetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        backoffFactor: 2.0,
        maxDelay: Duration(seconds: 10),
        jitter: false,
      );
      expect(
          policy.delayFor(0), const Duration(milliseconds: 100)); // 100 * 2^0
      expect(
          policy.delayFor(1), const Duration(milliseconds: 200)); // 100 * 2^1
      expect(
          policy.delayFor(2), const Duration(milliseconds: 400)); // 100 * 2^2
      expect(policy.delayFor(3), const Duration(milliseconds: 800));
    });

    test('delayFor is capped at maxDelay', () {
      const policy = EspRetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        backoffFactor: 10.0,
        maxDelay: Duration(milliseconds: 500),
        jitter: false,
      );
      expect(policy.delayFor(0), const Duration(milliseconds: 100));
      expect(policy.delayFor(1), const Duration(milliseconds: 500)); // capped
      expect(policy.delayFor(2), const Duration(milliseconds: 500)); // capped
    });

    test('delayFor with jitter stays within ±25% of base delay', () {
      const policy = EspRetryPolicy(
        initialDelay: Duration(milliseconds: 200),
        backoffFactor: 1.0,
        jitter: true,
      );
      // Run many times to probabilistically cover the range.
      for (var i = 0; i < 50; i++) {
        final delay = policy.delayFor(0).inMilliseconds;
        // factor ∈ [0.75, 1.25) → delay ∈ [150, 250)
        expect(delay, greaterThanOrEqualTo(150));
        expect(delay, lessThanOrEqualTo(250));
      }
    });

    test('delayFor returns 0 ms when initial delay is 0', () {
      const policy = EspRetryPolicy(
        initialDelay: Duration.zero,
        jitter: false,
      );
      expect(policy.delayFor(0), Duration.zero);
    });
  });
}
