// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Fake transport helpers ────────────────────────────────────────────────────

typedef _Handler = Future<EspResponse> Function(EspCommand);

/// A configurable fake transport that executes user-supplied handlers per call.
class _ScriptedTransport implements EspTransportInterface {
  _ScriptedTransport(this._handlers);

  final List<_Handler> _handlers;
  int _callCount = 0;
  bool _open = false;

  int get callCount => _callCount;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(EspConfig config) async => _open = true;
  @override
  Future<void> close() async => _open = false;
  @override
  Future<void> resetToBootloader() async {}
  @override
  Future<void> changeBaud(int _) async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout}) {
    if (_callCount >= _handlers.length) {
      throw const EspError(
          type: EspErrorType.timeout, message: 'no more handlers');
    }
    return _handlers[_callCount++](command);
  }
}

EspResponse _ok(EspCommandOpcode opcode) => EspResponse(
      opcode: opcode,
      value: 0,
      data: Uint8List(0),
      status: 0,
      error: 0,
    );

EspError _err(EspErrorType type) => EspError(type: type, message: type.name);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EspResilientTransport – delegation', () {
    test('delegates open/close/resetToBootloader/changeBaud to inner',
        () async {
      var openCalled = false;
      var closeCalled = false;
      var resetCalled = false;
      var baudCalled = false;

      final inner = _ScriptedTransport([]);
      // Wrap with a tiny subclass that flags calls.
      final resilient = _DelegationSpy(
        inner,
        onOpen: () => openCalled = true,
        onClose: () => closeCalled = true,
        onReset: () => resetCalled = true,
        onBaud: () => baudCalled = true,
      );

      await resilient.open(const EspConfig(portName: 'COM1'));
      await resilient.close();
      await resilient.resetToBootloader();
      await resilient.changeBaud(115200);

      expect(openCalled, isTrue);
      expect(closeCalled, isTrue);
      expect(resetCalled, isTrue);
      expect(baudCalled, isTrue);
    });
  });

  group('EspResilientTransport – retry', () {
    test('succeeds on the first attempt without retry', () async {
      final inner = _ScriptedTransport([
        (cmd) async => _ok(cmd.opcode),
      ]);
      final t =
          EspResilientTransport(inner, retryPolicy: const EspRetryPolicy());
      await t.open(const EspConfig(portName: 'COM1'));
      final response = await t.sendCommand(
        EspCommand(opcode: EspCommandOpcode.readReg, data: Uint8List(4)),
      );
      expect(response.isSuccess, isTrue);
      expect(inner.callCount, 1);
    });

    test('retries on timeout and succeeds on the second attempt', () async {
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
        (cmd) async => _ok(cmd.opcode),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: const EspRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          jitter: false,
        ),
      );
      await t.open(const EspConfig(portName: 'COM1'));
      final response = await t.sendCommand(
        EspCommand(opcode: EspCommandOpcode.readReg, data: Uint8List(4)),
      );
      expect(response.isSuccess, isTrue);
      expect(inner.callCount, 2);
    });

    test('retries on partialPacket', () async {
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.partialPacket),
        (cmd) async => _ok(cmd.opcode),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: const EspRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          jitter: false,
        ),
      );
      await t.open(const EspConfig(portName: 'COM1'));
      await t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync));
      expect(inner.callCount, 2);
    });

    test('does NOT retry on non-retryable errors', () async {
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.syncFailed),
        (cmd) async => _ok(cmd.opcode),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: const EspRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          retryOn: {EspErrorType.timeout},
        ),
      );
      await t.open(const EspConfig(portName: 'COM1'));
      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()
            .having((e) => e.type, 'type', EspErrorType.syncFailed)),
      );
      expect(inner.callCount, 1); // no retry
    });

    test('exhausts all attempts and rethrows the last error', () async {
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
        (_) async => throw _err(EspErrorType.timeout),
        (_) async => throw _err(EspErrorType.timeout),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: const EspRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          jitter: false,
        ),
      );
      await t.open(const EspConfig(portName: 'COM1'));
      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()
            .having((e) => e.type, 'type', EspErrorType.timeout)),
      );
      expect(inner.callCount, 3);
    });

    test('EspRetryPolicy.noRetry sends exactly once', () async {
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: EspRetryPolicy.noRetry,
      );
      await t.open(const EspConfig(portName: 'COM1'));
      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      expect(inner.callCount, 1);
    });
  });

  group('EspResilientTransport – circuit breaker', () {
    test('records success and keeps breaker closed', () async {
      final breaker = EspCircuitBreaker(
          failureThreshold: 3, tripOn: {EspErrorType.timeout});
      final inner = _ScriptedTransport([
        (cmd) async => _ok(cmd.opcode),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: EspRetryPolicy.noRetry,
        circuitBreaker: breaker,
      );
      await t.open(const EspConfig(portName: 'COM1'));
      await t.sendCommand(
          EspCommand(opcode: EspCommandOpcode.readReg, data: Uint8List(4)));
      expect(breaker.state, EspCircuitBreakerState.closed);
      expect(breaker.failureCount, 0);
    });

    test('records failure and trips breaker after threshold', () async {
      final breaker = EspCircuitBreaker(
        failureThreshold: 2,
        tripOn: {EspErrorType.timeout},
        resetTimeout: const Duration(seconds: 60),
      );
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
        (_) async => throw _err(EspErrorType.timeout),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: EspRetryPolicy.noRetry,
        circuitBreaker: breaker,
      );
      await t.open(const EspConfig(portName: 'COM1'));

      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      expect(breaker.state, EspCircuitBreakerState.closed);
      expect(breaker.failureCount, 1);

      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      expect(breaker.state, EspCircuitBreakerState.open);
    });

    test('throws circuitBreakerOpen when breaker is open', () async {
      final breaker = EspCircuitBreaker(
        failureThreshold: 1,
        tripOn: {EspErrorType.timeout},
        resetTimeout: const Duration(seconds: 60),
      );
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: EspRetryPolicy.noRetry,
        circuitBreaker: breaker,
      );
      await t.open(const EspConfig(portName: 'COM1'));

      // Trip the breaker.
      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      expect(breaker.state, EspCircuitBreakerState.open);

      // Next call must be blocked immediately.
      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()
            .having((e) => e.type, 'type', EspErrorType.circuitBreakerOpen)),
      );
      // Inner transport was NOT called again.
      expect(inner.callCount, 1);
    });

    test('lets a probe through after resetTimeout and closes on success',
        () async {
      final breaker = EspCircuitBreaker(
        failureThreshold: 1,
        successThreshold: 1,
        resetTimeout: const Duration(milliseconds: 5),
        tripOn: {EspErrorType.timeout},
      );
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout), // trips
        (cmd) async => _ok(cmd.opcode), // probe succeeds
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: EspRetryPolicy.noRetry,
        circuitBreaker: breaker,
      );
      await t.open(const EspConfig(portName: 'COM1'));

      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      expect(breaker.state, EspCircuitBreakerState.open);

      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Probe: allowsRequest auto-transitions to halfOpen.
      final response = await t.sendCommand(
        EspCommand(opcode: EspCommandOpcode.readReg, data: Uint8List(4)),
      );
      expect(response.isSuccess, isTrue);
      expect(breaker.state, EspCircuitBreakerState.closed);
    });
  });

  group('EspResilientTransport – combined retry + circuit breaker', () {
    test('retry exhaustion counts as one failure towards the breaker',
        () async {
      // failureThreshold = 1: the first EspError reaching the breaker trips it.
      // But with maxAttempts=3, there are 3 inner calls before the error
      // is propagated. The breaker should see 3 failures.
      final breaker = EspCircuitBreaker(
        failureThreshold: 2,
        tripOn: {EspErrorType.timeout},
        resetTimeout: const Duration(seconds: 60),
      );
      final inner = _ScriptedTransport([
        (_) async => throw _err(EspErrorType.timeout),
        (_) async => throw _err(EspErrorType.timeout),
        (_) async => throw _err(EspErrorType.timeout),
      ]);
      final t = EspResilientTransport(
        inner,
        retryPolicy: const EspRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          jitter: false,
        ),
        circuitBreaker: breaker,
      );
      await t.open(const EspConfig(portName: 'COM1'));

      await expectLater(
        t.sendCommand(EspCommand(opcode: EspCommandOpcode.sync)),
        throwsA(isA<EspError>()),
      );
      // 3 inner calls → 3 breaker failures → threshold 2 already crossed.
      expect(breaker.state, EspCircuitBreakerState.open);
      expect(inner.callCount, 3);
    });
  });

  group('EspResilientTransport – accessors', () {
    test('exposes circuitBreaker and retryPolicy', () {
      final inner = _ScriptedTransport([]);
      const policy = EspRetryPolicy(maxAttempts: 5);
      final breaker = EspCircuitBreaker();
      final t = EspResilientTransport(inner,
          retryPolicy: policy, circuitBreaker: breaker);
      expect(t.retryPolicy, same(policy));
      expect(t.circuitBreaker, same(breaker));
    });

    test('circuitBreaker is null when not provided', () {
      final t = EspResilientTransport(_ScriptedTransport([]));
      expect(t.circuitBreaker, isNull);
    });
  });
}

// ─── Helper: spy for delegation test ─────────────────────────────────────────

class _DelegationSpy extends EspResilientTransport {
  _DelegationSpy(
    super.inner, {
    required this.onOpen,
    required this.onClose,
    required this.onReset,
    required this.onBaud,
  });

  final void Function() onOpen;
  final void Function() onClose;
  final void Function() onReset;
  final void Function() onBaud;

  @override
  Future<void> open(EspConfig config) {
    onOpen();
    return super.open(config);
  }

  @override
  Future<void> close() {
    onClose();
    return super.close();
  }

  @override
  Future<void> resetToBootloader() {
    onReset();
    return super.resetToBootloader();
  }

  @override
  Future<void> changeBaud(int baud) {
    onBaud();
    return super.changeBaud(baud);
  }
}
