// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:professional_esptool_demo/app_strings.dart';

void main() {
  runApp(const ProfessionalEspToolDemoApp());
}

class ProfessionalEspToolDemoApp extends StatefulWidget {
  const ProfessionalEspToolDemoApp({super.key});

  @override
  State<ProfessionalEspToolDemoApp> createState() =>
      _ProfessionalEspToolDemoAppState();
}

class _ProfessionalEspToolDemoAppState
    extends State<ProfessionalEspToolDemoApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.t(_locale, 'appTitle'),
      themeMode: _themeMode,
      locale: _locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42A5F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _SplashGate(
        locale: _locale,
        onThemeChanged: (mode) => setState(() => _themeMode = mode),
        onLocaleChanged: (locale) => setState(() => _locale = locale),
        themeMode: _themeMode,
      ),
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate({
    required this.locale,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onLocaleChanged,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return _HomePage(
        locale: widget.locale,
        onThemeChanged: widget.onThemeChanged,
        onLocaleChanged: widget.onLocaleChanged,
        themeMode: widget.themeMode,
      );
    }

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.memory_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppStrings.t(widget.locale, 'splash'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatefulWidget {
  const _HomePage({
    required this.locale,
    required this.onThemeChanged,
    required this.onLocaleChanged,
    required this.themeMode,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late EspTransportInterface _transport;
  late ConnectionService _connectionService;
  late ChipDetectionService _chipDetectionService;
  late InfoService _infoService;
  late FlashService _flashService;

  final List<_LogEntry> _logs = <_LogEntry>[];
  final SerialManager _serialManager = SerialManager();
  List<SerialPortInfo> _availablePorts = <SerialPortInfo>[];
  bool _loadingPorts = false;
  String? _selectedPortName;
  bool _connected = false;
  String _chip = '-';
  String _mac = '-';
  String _flash = '-';

  @override
  void initState() {
    super.initState();
    _initializeTransport();
    _refreshPorts();
  }

  void _initializeTransport({String? portName}) {
    final logger = _onTransportLog;
    
    // Use scripted demo transport (for demo purposes on Windows)
    // On supported platforms with real serial hardware, EspTransport can be used
    _transport = _ScriptedTransport(logger: logger);
    
    _connectionService = ConnectionService(_transport);
    _chipDetectionService = ChipDetectionService(_transport);
    _infoService = InfoService(
        transport: _transport, chipDetectionService: _chipDetectionService);
    _flashService = FlashService(transport: _transport);
  }

  @override
  void dispose() {
    if (_transport.isOpen) {
      _transport.close();
    }
    super.dispose();
  }

  void _log(String message, {LogLevel level = LogLevel.info}) {
    final entry = _LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );
    debugPrint('[${entry.level.name.toUpperCase()}] ${entry.message}');
    setState(() => _logs.insert(0, entry));
  }

  void _onTransportLog(EspTransportLogEntry entry) {
    final response = entry.response;
    final level = switch (entry.type) {
      EspTransportLogType.commandSent => LogLevel.info,
      EspTransportLogType.responseReceived =>
        response != null && response.isSuccess ? LogLevel.info : LogLevel.warning,
      EspTransportLogType.transportError => LogLevel.error,
    };
    _log(_formatTransportLog(entry), level: level);
  }

  String _formatTransportLog(EspTransportLogEntry entry) {
    final timestamp = entry.timestamp.toIso8601String();
    final opcode = entry.opcode;
    final opcodeLabel = opcode == null
        ? '-'
        : '${opcode.name}(0x${opcode.value.toRadixString(16).padLeft(2, '0')})';
    final rawPacket =
        entry.rawPacket == null ? '-' : _toHex(entry.rawPacket!, maxBytes: 128);
    final rawFrame =
        entry.rawFrame == null ? '-' : _toHex(entry.rawFrame!, maxBytes: 128);

    return switch (entry.type) {
      EspTransportLogType.commandSent =>
        '[$timestamp] CMD $opcodeLabel\n'
            'raw.packet: $rawPacket\n'
            'raw.frame: $rawFrame\n'
            'decoded: checksum=0x${entry.command?.checksum.toRadixString(16).padLeft(2, '0') ?? '--'} '
                'dataLen=${entry.command?.data.length ?? 0}',
      EspTransportLogType.responseReceived =>
        '[$timestamp] RSP $opcodeLabel\n'
            'raw.packet: $rawPacket\n'
            'raw.frame: $rawFrame\n'
            'decoded: value=0x${entry.response?.value.toRadixString(16).padLeft(8, '0') ?? '--------'} '
            'status=${entry.response?.status ?? '-'} error=${entry.response?.error ?? '-'} '
            'dataLen=${entry.response?.data.length ?? 0}',
      EspTransportLogType.transportError =>
        '[$timestamp] ERR $opcodeLabel\n'
            'message: ${entry.message ?? 'unknown transport error'}',
    };
  }

  String _toHex(Uint8List bytes, {required int maxBytes}) {
    final visibleLength = bytes.length > maxBytes ? maxBytes : bytes.length;
    final visible = bytes
        .take(visibleLength)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    if (bytes.length <= maxBytes) {
      return visible;
    }
    return '$visible ... (+${bytes.length - maxBytes} bytes)';
  }

  Future<void> _connect() async {
    final selectedPort = _selectedPortName ?? 'DEMO-COM';
    
    // Reinitialize transport with selected port
    _initializeTransport(portName: selectedPort);
    
    final config = EspConfig(
      portName: selectedPort,
      initialBaudRate: 115200,
      timeout: const Duration(seconds: 5),
      syncRetries: 16,
    );
    
    final result = await _connectionService.connect(config);
    result.fold(
      (_) {
        setState(() => _connected = true);
        _log('Connection successful on $selectedPort');
      },
      (error) => _log('Connection failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _refreshPorts() async {
    setState(() => _loadingPorts = true);
    try {
      final ports = await _serialManager.getAvailablePorts();
      if (!mounted) {
        return;
      }
      setState(() {
        _availablePorts = ports;
        final stillAvailable = _selectedPortName != null &&
            ports.any((port) => port.portName == _selectedPortName);
        final newSelection = stillAvailable
            ? _selectedPortName
            : (ports.isNotEmpty ? ports.first.portName : null);
        
        // If port selection changed, disconnect and reset state
        if (newSelection != _selectedPortName) {
          _selectedPortName = newSelection;
          _connected = false;
          _chip = '-';
          _mac = '-';
          _flash = '-';
        } else {
          _selectedPortName = newSelection;
        }
      });
      _log('Detected ${ports.length} serial port(s)');
    } on SerialError catch (error) {
      _log('Failed to load serial ports: ${error.message}', level: LogLevel.error);
    } on ArgumentError catch (error) {
      _log('Serial plugin unavailable: ${error.message}', level: LogLevel.warning);
    } finally {
      if (mounted) {
        setState(() => _loadingPorts = false);
      }
    }
  }

  String _describePort(SerialPortInfo port) {
    final description = port.description.trim();
    if (description.isEmpty) {
      return port.portName;
    }
    return '${port.portName} - $description';
  }

  Future<void> _detectChip() async {
    final result = await _chipDetectionService.detect();
    result.fold(
      (chip) {
        setState(() => _chip = chip.description);
        _log('Chip detected: ${chip.description}');
      },
      (error) =>
          _log('Chip detection failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _readMac() async {
    final result = await _infoService.getMac();
    result.fold(
      (mac) {
        setState(() => _mac = mac);
        _log('MAC: $mac');
      },
      (error) => _log('MAC read failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _flashInfo() async {
    final result = await _infoService.getFlashId();
    result.fold(
      (info) {
        final desc =
            '${info.manufacturerName ?? 'Unknown'} - ${info.capacityBytes ?? 0} bytes';
        setState(() => _flash = desc);
        _log('Flash info: $desc');
      },
      (error) =>
          _log('Flash info failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _writeFlash() async {
    final image =
        Uint8List.fromList(List<int>.generate(4096, (index) => index % 255));
    final result = await _flashService.writeFlash(
      FlashParameters(
        offset: 0x1000,
        data: image,
        verify: true,
        onProgress: (progress) {
          _log('Write progress: ${progress.current}/${progress.total}');
          return Stream<EspProgress>.value(progress);
        },
      ),
    );

    result.fold(
      (_) => _log('Flash write completed'),
      (error) =>
          _log('Flash write failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _eraseFlash() async {
    final result = await _flashService.eraseFlash();
    result.fold(
      (_) => _log('Flash erase completed'),
      (error) =>
          _log('Flash erase failed: ${error.message}', level: LogLevel.error),
    );
  }

  Future<void> _readMd5() async {
    final result = await _flashService.md5Flash(0x1000, 4096);
    result.fold(
      (hash) => _log('Device MD5: $hash'),
      (error) => _log('MD5 failed: ${error.message}', level: LogLevel.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => AppStrings.t(widget.locale, key);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('appTitle')),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<Locale>(
              value: widget.locale,
              selectedItemBuilder: (context) => AppStrings.supportedLocales
                  .map(
                    (locale) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(AppStrings.languageFlag(locale)),
                        const SizedBox(width: 8),
                        Text(AppStrings.languageDisplayName(locale)),
                      ],
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  widget.onLocaleChanged(value);
                }
              },
              items: AppStrings.supportedLocales
                  .map(
                    (locale) => DropdownMenuItem(
                      value: locale,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppStrings.languageFlag(locale)),
                          const SizedBox(width: 8),
                          Text(AppStrings.languageDisplayName(locale)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<ThemeMode>(
              value: widget.themeMode,
              onChanged: (value) {
                if (value != null) {
                  widget.onThemeChanged(value);
                }
              },
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.brightness_auto_rounded),
                      const SizedBox(width: 8),
                      Text(t('system')),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.light_mode_rounded),
                      const SizedBox(width: 8),
                      Text(t('light')),
                    ],
                  ),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.dark_mode_rounded),
                      const SizedBox(width: 8),
                      Text(t('dark')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('subtitle'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.usb_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('serialPorts'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              hint: Text(t('noSerialPorts')),
                              value: _selectedPortName,
                              onChanged: _availablePorts.isEmpty
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() {
                                          _selectedPortName = value;
                                          _connected = false;
                                          _chip = '-';
                                          _mac = '-';
                                          _flash = '-';
                                          // Reinitialize transport for new port
                                          _initializeTransport(portName: value);
                                        });
                                      }
                                    },
                              items: _availablePorts
                                  .map(
                                    (port) => DropdownMenuItem<String>(
                                      value: port.portName,
                                      child: Text(_describePort(port)),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: t('refreshPorts'),
                      onPressed: _loadingPorts ? null : _refreshPorts,
                      icon: _loadingPorts
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(onPressed: _connect, child: Text(t('connect'))),
                FilledButton.tonal(
                    onPressed: _connected ? _detectChip : null,
                    child: Text(t('detectChip'))),
                FilledButton.tonal(
                    onPressed: _connected ? _readMac : null,
                    child: Text(t('readMac'))),
                FilledButton.tonal(
                    onPressed: _connected ? _flashInfo : null,
                    child: Text(t('flashInfo'))),
                FilledButton.tonal(
                    onPressed: _connected ? _writeFlash : null,
                    child: Text(t('writeFlash'))),
                FilledButton.tonal(
                    onPressed: _connected ? _eraseFlash : null,
                    child: Text(t('eraseFlash'))),
                FilledButton.tonal(
                    onPressed: _connected ? _readMd5 : null,
                    child: Text(t('readMd5'))),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(child: Text('${t('chip')}: $_chip')),
                    Expanded(child: Text('${t('mac')}: $_mac')),
                    Expanded(child: Text('${t('flash')}: $_flash')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(t('logs'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final logEntry = _logs[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: _logBackgroundColor(context, logEntry.level),
                        border: Border(
                          left: BorderSide(
                            color: _logAccentColor(context, logEntry.level),
                            width: 3,
                          ),
                        ),
                      ),
                      child: ListTile(
                        dense: false,
                        leading: Icon(
                          _logIcon(logEntry.level),
                          color: _logAccentColor(context, logEntry.level),
                        ),
                        title: Text(
                          logEntry.message,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: _logTextColor(context, logEntry.level),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _logBackgroundColor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.info => scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      LogLevel.warning => Colors.amber.withValues(alpha: 0.14),
      LogLevel.error => scheme.errorContainer.withValues(alpha: 0.38),
    };
  }

  Color _logTextColor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.info => scheme.onSurface,
      LogLevel.warning => Colors.amber.shade900,
      LogLevel.error => scheme.onErrorContainer,
    };
  }

  Color _logAccentColor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.info => Colors.blueGrey,
      LogLevel.warning => Colors.amber.shade800,
      LogLevel.error => scheme.error,
    };
  }

  IconData _logIcon(LogLevel level) => switch (level) {
        LogLevel.info => Icons.info_outline_rounded,
        LogLevel.warning => Icons.warning_amber_rounded,
        LogLevel.error => Icons.error_outline_rounded,
      };
}

enum LogLevel { info, warning, error }

class _LogEntry {
  const _LogEntry({
    required this.message,
    required this.level,
    required this.timestamp,
  });

  final String message;
  final LogLevel level;
  final DateTime timestamp;
}

class _ScriptedTransport implements EspTransportInterface {
  _ScriptedTransport({this.logger});

  final EspTransportLogger? logger;

  final Map<EspCommandOpcode, Queue<EspResponse>> _responses =
      <EspCommandOpcode, Queue<EspResponse>>{
    EspCommandOpcode.sync: Queue<EspResponse>()
      ..add(_ok(EspCommandOpcode.sync)),
    EspCommandOpcode.readReg: Queue<EspResponse>()
      ..add(_ok(EspCommandOpcode.readReg, value: 0x00F01D83))
      ..add(_ok(EspCommandOpcode.readReg, value: 0x33445566))
      ..add(_ok(EspCommandOpcode.readReg, value: 0x00001122)),
    EspCommandOpcode.flashBegin: Queue<EspResponse>()
      ..add(_ok(EspCommandOpcode.flashBegin)),
    EspCommandOpcode.flashData: Queue<EspResponse>()
      ..add(_ok(EspCommandOpcode.flashData)),
    EspCommandOpcode.flashEnd: Queue<EspResponse>()
      ..add(_ok(EspCommandOpcode.flashEnd)),
    EspCommandOpcode.flashMd5: Queue<EspResponse>()
      ..add(
        _ok(
          EspCommandOpcode.flashMd5,
          data:
              Uint8List.fromList('08d6c05a21512a79a1dfeb9d2a8f262f'.codeUnits),
        ),
      ),
    EspCommandOpcode.spiSetParams: Queue<EspResponse>()
      ..add(
        _ok(
          EspCommandOpcode.spiSetParams,
          data: Uint8List.fromList(<int>[0xEF, 0x40, 0x18]),
        ),
      ),
  };

  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Future<void> open(EspConfig config) async {
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  Future<void> resetToBootloader() async {}

  @override
  Future<void> changeBaud(int newBaud) async {}

  @override
  Future<EspResponse> sendCommand(EspCommand command,
      {Duration? timeout}) async {
    final requestPacket = _buildCommandPacket(command);
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.commandSent,
        timestamp: DateTime.now(),
        opcode: command.opcode,
        rawPacket: Uint8List.fromList(requestPacket),
        command: command,
      ),
    );

    final queue = _responses[command.opcode];
    final response =
        queue == null || queue.isEmpty ? _ok(command.opcode) : queue.removeFirst();
    final responsePacket = _buildResponsePacket(response);
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.responseReceived,
        timestamp: DateTime.now(),
        opcode: response.opcode,
        rawPacket: Uint8List.fromList(responsePacket),
        response: response,
        command: command,
      ),
    );
    return response;
  }

  static EspResponse _ok(
    EspCommandOpcode opcode, {
    int value = 0,
    Uint8List? data,
  }) {
    return EspResponse(
      opcode: opcode,
      value: value,
      data: data ?? Uint8List(0),
      status: 0,
      error: 0,
    );
  }

  static Uint8List _buildCommandPacket(EspCommand command) {
    final packet = Uint8List(8 + command.data.length);
    final data = ByteData.sublistView(packet);
    data.setUint8(0, 0x00);
    data.setUint8(1, command.opcode.value);
    data.setUint16(2, command.data.length, Endian.little);
    data.setUint32(4, command.checksum, Endian.little);
    packet.setRange(8, packet.length, command.data);
    return packet;
  }

  static Uint8List _buildResponsePacket(EspResponse response) {
    final packet = Uint8List(8 + response.data.length + 2);
    final data = ByteData.sublistView(packet);
    data.setUint8(0, 0x01);
    data.setUint8(1, response.opcode.value);
    data.setUint16(2, response.data.length + 2, Endian.little);
    data.setUint32(4, response.value, Endian.little);
    packet.setRange(8, 8 + response.data.length, response.data);
    packet[packet.length - 2] = response.status;
    packet[packet.length - 1] = response.error;
    return packet;
  }
}
