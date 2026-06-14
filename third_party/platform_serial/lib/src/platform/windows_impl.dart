// coverage:ignore-file
// ignore_for_file: close_sinks

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../models/serial_config.dart';
import '../models/serial_control_signals.dart';
import '../models/serial_error.dart';
import '../models/serial_port_info.dart';
import 'serial_platform_interface.dart';

const int _kFlutterSerialSuccess = 0;
const int _kFlutterSerialInvalidArgument = 1;
const int _kFlutterSerialPortNotFound = 2;
const int _kFlutterSerialPortAlreadyOpen = 3;
const int _kFlutterSerialIoError = 4;
const int _kFlutterSerialTimeout = 5;

const int _windowsSignalRts = 1 << 0;
const int _windowsSignalCts = 1 << 1;
const int _windowsSignalDtr = 1 << 2;
const int _windowsSignalDsr = 1 << 3;
const int _windowsSignalDcd = 1 << 4;

/// Windows FFI implementation.
class WindowsSerialImpl implements SerialPlatformInterface {
  factory WindowsSerialImpl() => _instance;

  WindowsSerialImpl._();

  static final WindowsSerialImpl _instance = WindowsSerialImpl._();
  static final _FlutterSerialBindings _bindings =
      _FlutterSerialBindings(_openLibrary());

  final Map<String, _WindowsPortContext> _ports = {};

  static DynamicLibrary _openLibrary() {
    if (!Platform.isWindows) {
      throw UnsupportedError('WindowsSerialImpl is available on Windows only.');
    }
    return DynamicLibrary.open('platform_serial.dll');
  }

  @override
  Future<List<SerialPortInfo>> getAvailablePorts() async {
    final jsonPointer = calloc<Pointer<Utf8>>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.getPorts(
        jsonPointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error retrieving Windows ports',
      );

      final payloadPointer = jsonPointer.value;
      if (payloadPointer == nullptr) {
        return [];
      }

      final payload = payloadPointer.toDartString();
      _bindings.freeString(payloadPointer);

      final decoded = jsonDecode(payload) as List<dynamic>;
      return decoded.map((dynamic item) {
        final port = Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
        return SerialPortInfo(
          portName: port['portName'] as String? ?? 'Unknown',
          description: port['description'] as String? ?? '',
          vendorId: port['vendorId'] as String?,
          productId: port['productId'] as String?,
          serialNumber: port['serialNumber'] as String?,
          isOpen: port['isOpen'] as bool? ?? false,
          platform: port['platform'] as String? ?? 'windows',
        );
      }).toList(growable: false);
    } finally {
      calloc.free(jsonPointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> openPort(SerialConfig config) async {
    if (_ports.containsKey(config.portName)) {
      throw SerialError(
        type: SerialErrorType.portAlreadyOpen,
        message: 'Port ${config.portName} is already open.',
      );
    }

    final portNamePointer = config.portName.toNativeUtf16();
    final portIdPointer = calloc<Int64>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.openPort(
        portNamePointer,
        config.baudRate,
        config.dataBits,
        config.stopBits.index,
        config.parity.index,
        config.flowControl.index,
        config.readTimeout.inMilliseconds,
        config.writeTimeout.inMilliseconds,
        portIdPointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error opening port on Windows',
      );

      _ports[config.portName] = _WindowsPortContext(
        portName: config.portName,
        portId: portIdPointer.value,
      );
    } finally {
      calloc.free(portNamePointer);
      calloc.free(portIdPointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> closePort(String portName) async {
    final context = _requireContext(portName);
    context.stopPolling();

    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.closePort(
        context.portId,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error closing port on Windows',
      );
      _ports.remove(portName);
      await context.closeController();
    } finally {
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<Uint8List> readData(String portName, int length) async {
    if (length <= 0) {
      return Uint8List(0);
    }

    final context = _requireContext(portName);
    final buffer = calloc<Uint8>(length);
    final bytesReadPointer = calloc<Int32>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.readPort(
        context.portId,
        buffer,
        length,
        bytesReadPointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error reading on Windows',
      );

      return Uint8List.fromList(
        buffer.asTypedList(bytesReadPointer.value),
      );
    } finally {
      calloc.free(buffer);
      calloc.free(bytesReadPointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<int> writeData(String portName, Uint8List data) async {
    final context = _requireContext(portName);
    final input = calloc<Uint8>(data.length);
    final bytesWrittenPointer = calloc<Int32>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      input.asTypedList(data.length).setAll(0, data);

      final status = _bindings.writePort(
        context.portId,
        input,
        data.length,
        bytesWrittenPointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error writing on Windows',
      );

      return bytesWrittenPointer.value;
    } finally {
      calloc.free(input);
      calloc.free(bytesWrittenPointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<int> bytesAvailable(String portName) async {
    final context = _requireContext(portName);
    final bytesAvailablePointer = calloc<Int32>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.bytesAvailable(
        context.portId,
        bytesAvailablePointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error retrieving available bytes on Windows',
      );

      return bytesAvailablePointer.value;
    } finally {
      calloc.free(bytesAvailablePointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> resetBuffers(String portName) async {
    final context = _requireContext(portName);
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.resetPortBuffers(
        context.portId,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error resetting buffers on Windows',
      );
    } finally {
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> flush(String portName) async {
    final context = _requireContext(portName);
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.flushPort(
        context.portId,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error flushing buffer on Windows',
      );
    } finally {
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<SerialControlSignals> getControlSignals(String portName) async {
    final context = _requireContext(portName);
    final maskPointer = calloc<Uint32>();
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.getControlSignals(
        context.portId,
        maskPointer,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error reading control signals on Windows',
      );
      final mask = maskPointer.value;
      return SerialControlSignals(
        mask: mask,
        rts: (mask & _windowsSignalRts) != 0,
        cts: (mask & _windowsSignalCts) != 0,
        dtr: (mask & _windowsSignalDtr) != 0,
        dsr: (mask & _windowsSignalDsr) != 0,
        dcd: (mask & _windowsSignalDcd) != 0,
      );
    } finally {
      calloc.free(maskPointer);
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> setDtr(String portName, bool enabled) async {
    final context = _requireContext(portName);
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.setDtr(
        context.portId,
        enabled ? 1 : 0,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error setting DTR on Windows',
      );
    } finally {
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Future<void> setRts(String portName, bool enabled) async {
    final context = _requireContext(portName);
    final errorCodePointer = calloc<Uint32>();
    final errorMessagePointer = calloc<Pointer<Utf8>>();

    try {
      final status = _bindings.setRts(
        context.portId,
        enabled ? 1 : 0,
        errorCodePointer,
        errorMessagePointer,
      );
      _ensureSuccess(
        status,
        errorCodePointer.value,
        errorMessagePointer.value,
        'Error setting RTS on Windows',
      );
    } finally {
      calloc.free(errorCodePointer);
      calloc.free(errorMessagePointer);
    }
  }

  @override
  Stream<dynamic> getEventStream(String portName) {
    final context = _requireContext(portName);
    final controller =
        context.controller ??= StreamController<dynamic>.broadcast(
      onListen: () => _startPolling(context),
      onCancel: () {
        if (!(context.controller?.hasListener ?? false)) {
          context.stopPolling();
        }
      },
    );
    return controller.stream;
  }

  _WindowsPortContext _requireContext(String portName) {
    final context = _ports[portName];
    if (context == null) {
      throw SerialError(
        type: SerialErrorType.portClosed,
        message: 'Port $portName is not open.',
      );
    }
    return context;
  }

  void _startPolling(_WindowsPortContext context) {
    if (context.poller != null) {
      return;
    }

    context.poller =
        Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final controller = context.controller;
      if (controller == null ||
          controller.isClosed ||
          !controller.hasListener) {
        context.stopPolling();
        return;
      }
      if (context.isPolling) {
        return;
      }

      context.isPolling = true;
      try {
        final available = await bytesAvailable(context.portName);
        if (available <= 0) {
          return;
        }

        final data = await readData(
          context.portName,
          available > 4096 ? 4096 : available,
        );
        if (data.isNotEmpty) {
          controller.add({
            'type': 'data',
            'data': data,
          });
        }
      } on SerialError catch (error) {
        controller.add({
          'type': 'error',
          'message': error.message,
        });
      } finally {
        context.isPolling = false;
      }
    });
  }

  void _ensureSuccess(
    int status,
    int windowsError,
    Pointer<Utf8> messagePointer,
    String fallbackMessage,
  ) {
    if (status == _kFlutterSerialSuccess) {
      if (messagePointer != nullptr) {
        _bindings.freeString(messagePointer);
      }
      return;
    }

    final message = _readAndReleaseMessage(messagePointer, fallbackMessage);
    throw SerialError(
      type: _mapStatus(status),
      message: '$message (Windows error code: $windowsError)',
    );
  }

  String _readAndReleaseMessage(
    Pointer<Utf8> messagePointer,
    String fallbackMessage,
  ) {
    if (messagePointer == nullptr) {
      return fallbackMessage;
    }

    final message = messagePointer.toDartString();
    _bindings.freeString(messagePointer);
    return message;
  }

  SerialErrorType _mapStatus(int status) {
    switch (status) {
      case _kFlutterSerialInvalidArgument:
        return SerialErrorType.configurationError;
      case _kFlutterSerialPortNotFound:
        return SerialErrorType.portNotFound;
      case _kFlutterSerialPortAlreadyOpen:
        return SerialErrorType.portAlreadyOpen;
      case _kFlutterSerialTimeout:
        return SerialErrorType.timeout;
      case _kFlutterSerialIoError:
        return SerialErrorType.ioError;
      default:
        return SerialErrorType.unknown;
    }
  }
}

final class _WindowsPortContext {
  _WindowsPortContext({
    required this.portName,
    required this.portId,
  });

  final String portName;
  final int portId;
  StreamController<dynamic>? controller;
  Timer? poller;
  bool isPolling = false;

  void stopPolling() {
    poller?.cancel();
    poller = null;
  }

  Future<void> closeController() async {
    final existingController = controller;
    controller = null;
    if (existingController != null && !existingController.isClosed) {
      await existingController.close();
    }
  }
}

final class _FlutterSerialBindings {
  _FlutterSerialBindings(DynamicLibrary library)
      : getPorts = library.lookupFunction<_GetPortsNative, _GetPortsDart>(
          'platform_serial_get_ports',
        ),
        openPort = library.lookupFunction<_OpenPortNative, _OpenPortDart>(
          'platform_serial_open_port',
        ),
        closePort = library.lookupFunction<_ClosePortNative, _ClosePortDart>(
          'platform_serial_close_port',
        ),
        readPort = library.lookupFunction<_ReadPortNative, _ReadPortDart>(
          'platform_serial_read_port',
        ),
        writePort = library.lookupFunction<_WritePortNative, _WritePortDart>(
          'platform_serial_write_port',
        ),
        bytesAvailable =
            library.lookupFunction<_BytesAvailableNative, _BytesAvailableDart>(
                'platform_serial_bytes_available'),
        flushPort = library.lookupFunction<_FlushPortNative, _FlushPortDart>(
          'platform_serial_flush_port',
        ),
        resetPortBuffers = library
            .lookupFunction<_ResetPortBuffersNative, _ResetPortBuffersDart>(
          'platform_serial_reset_port_buffers',
        ),
        getControlSignals = library.lookupFunction<_GetControlSignalsNative,
            _GetControlSignalsDart>('platform_serial_get_control_signals'),
        setDtr = library.lookupFunction<_SetDtrNative, _SetDtrDart>(
          'platform_serial_set_dtr',
        ),
        setRts = library.lookupFunction<_SetRtsNative, _SetRtsDart>(
          'platform_serial_set_rts',
        ),
        freeString = library.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'platform_serial_free_string',
        );

  final _GetPortsDart getPorts;
  final _OpenPortDart openPort;
  final _ClosePortDart closePort;
  final _ReadPortDart readPort;
  final _WritePortDart writePort;
  final _BytesAvailableDart bytesAvailable;
  final _FlushPortDart flushPort;
  final _ResetPortBuffersDart resetPortBuffers;
  final _GetControlSignalsDart getControlSignals;
  final _SetDtrDart setDtr;
  final _SetRtsDart setRts;
  final _FreeStringDart freeString;
}

typedef _GetPortsNative = Int32 Function(
  Pointer<Pointer<Utf8>>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _GetPortsDart = int Function(
  Pointer<Pointer<Utf8>>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _OpenPortNative = Int32 Function(
  Pointer<Utf16>,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Int32,
  Pointer<Int64>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _OpenPortDart = int Function(
  Pointer<Utf16>,
  int,
  int,
  int,
  int,
  int,
  int,
  int,
  Pointer<Int64>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _ClosePortNative = Int32 Function(
  Int64,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _ClosePortDart = int Function(
  int,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _ReadPortNative = Int32 Function(
  Int64,
  Pointer<Uint8>,
  Int32,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _ReadPortDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _WritePortNative = Int32 Function(
  Int64,
  Pointer<Uint8>,
  Int32,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _WritePortDart = int Function(
  int,
  Pointer<Uint8>,
  int,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _BytesAvailableNative = Int32 Function(
  Int64,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _BytesAvailableDart = int Function(
  int,
  Pointer<Int32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _FlushPortNative = Int32 Function(
  Int64,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _FlushPortDart = int Function(
  int,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _ResetPortBuffersNative = Int32 Function(
  Int64,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _ResetPortBuffersDart = int Function(
  int,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _GetControlSignalsNative = Int32 Function(
  Int64,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _GetControlSignalsDart = int Function(
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _SetDtrNative = Int32 Function(
  Int64,
  Int32,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _SetDtrDart = int Function(
  int,
  int,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _SetRtsNative = Int32 Function(
  Int64,
  Int32,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);
typedef _SetRtsDart = int Function(
  int,
  int,
  Pointer<Uint32>,
  Pointer<Pointer<Utf8>>,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);
