// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:esptool_ui/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

typedef SerialPortsLoader = Future<List<SerialPortInfo>> Function();
typedef EspTransportFactory = EspTransportInterface Function(
  EspTransportLogger? logger,
);

void main() {
  runApp(const EsptoolUiApp());
}

EspTransportInterface _defaultTransportFactory(EspTransportLogger? logger) {
  return EspTransport(logger: logger);
}

Future<List<SerialPortInfo>> _defaultSerialPortsLoader() {
  return SerialManager().getAvailablePorts();
}

class EsptoolUiApp extends StatefulWidget {
  const EsptoolUiApp({
    super.key,
    this.serialPortsLoader,
    this.transportFactory = _defaultTransportFactory,
    this.splashDuration = const Duration(milliseconds: 1600),
  });

  final SerialPortsLoader? serialPortsLoader;
  final EspTransportFactory transportFactory;
  final Duration splashDuration;

  @override
  State<EsptoolUiApp> createState() => _EsptoolUiAppState();
}

class _EsptoolUiAppState extends State<EsptoolUiApp> {
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
        splashDuration: widget.splashDuration,
        serialPortsLoader: widget.serialPortsLoader ?? _defaultSerialPortsLoader,
        transportFactory: widget.transportFactory,
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
    required this.splashDuration,
    required this.serialPortsLoader,
    required this.transportFactory,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Locale> onLocaleChanged;
  final Duration splashDuration;
  final SerialPortsLoader serialPortsLoader;
  final EspTransportFactory transportFactory;

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.splashDuration, () {
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
        serialPortsLoader: widget.serialPortsLoader,
        transportFactory: widget.transportFactory,
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
    required this.serialPortsLoader,
    required this.transportFactory,
  });

  final Locale locale;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<Locale> onLocaleChanged;
  final SerialPortsLoader serialPortsLoader;
  final EspTransportFactory transportFactory;

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  late final EspTransportInterface _transport;
  late final ConnectionService _connectionService;
  late final ChipDetectionService _chipDetectionService;
  late final InfoService _infoService;
  late final FlashService _flashService;

  final List<_LogEntry> _logs = <_LogEntry>[];
  List<SerialPortInfo> _availablePorts = <SerialPortInfo>[];
  bool _loadingPorts = false;
  bool _serialPluginAvailable = true;
  String? _serialStatusMessage;
  String? _selectedPortName;
  bool _connected = false;
  String _chip = '-';
  String _mac = '-';
  String _flash = '-';

  @override
  void initState() {
    super.initState();
    _transport = widget.transportFactory(_onTransportLog);
    _connectionService = ConnectionService(_transport);
    _chipDetectionService = ChipDetectionService(_transport);
    _infoService = InfoService(
      transport: _transport,
      chipDetectionService: _chipDetectionService,
    );
    _flashService = FlashService(transport: _transport);
    _refreshPorts();
  }

  @override
  void dispose() {
    if (_transport.isOpen) {
      _transport.close();
    }
    super.dispose();
  }

  String _t(String key) => AppStrings.t(widget.locale, key);

  bool get _canConnect =>
      !_loadingPorts && _serialPluginAvailable && _selectedPortName != null;

  void _resetDeviceInfo() {
    _chip = '-';
    _mac = '-';
    _flash = '-';
  }

  void _log(String message, {LogLevel level = LogLevel.info}) {
    final entry = _LogEntry(
      message: message,
      level: level,
      timestamp: DateTime.now(),
    );
    debugPrint('[${entry.level.name.toUpperCase()}] ${entry.message}');
    if (!mounted) {
      return;
    }
    setState(() => _logs.insert(0, entry));
  }

  Future<void> _disconnectTransport() async {
    try {
      await _connectionService.disconnect();
    } catch (error) {
      _log('Disconnect warning: $error', level: LogLevel.warning);
    }
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
    final selectedPort = _selectedPortName;
    if (selectedPort == null) {
      _log(_t('selectSerialPort'), level: LogLevel.warning);
      return;
    }
    if (!_serialPluginAvailable) {
      _log(_serialStatusMessage ?? _t('serialPluginUnavailable'),
          level: LogLevel.warning);
      return;
    }

    if (_transport.isOpen) {
      await _disconnectTransport();
    }

    _log('Connecting to $selectedPort...');
    final config = EspConfig(
      portName: selectedPort,
      initialBaudRate: 115200,
      timeout: const Duration(seconds: 5),
      syncRetries: 16,
    );

    final result = await _connectionService.connect(config);
    if (!mounted) {
      return;
    }
    result.fold(
      (_) {
        setState(() => _connected = true);
        _log('Connection successful on $selectedPort');
      },
      (error) {
        setState(() => _connected = false);
        _log('Connection failed: ${error.message}', level: LogLevel.error);
      },
    );
  }

  Future<void> _refreshPorts() async {
    setState(() => _loadingPorts = true);

    try {
      final ports = await widget.serialPortsLoader();
      if (!mounted) {
        return;
      }

      final stillAvailable = _selectedPortName != null &&
          ports.any((port) => port.portName == _selectedPortName);
      final newSelection = stillAvailable
          ? _selectedPortName
          : (ports.isNotEmpty ? ports.first.portName : null);
      final selectionChanged = newSelection != _selectedPortName;
      final shouldDisconnect = selectionChanged && _transport.isOpen;

      setState(() {
        _serialPluginAvailable = true;
        _serialStatusMessage = ports.isEmpty ? _t('noSerialPorts') : null;
        _availablePorts = ports;
        _selectedPortName = newSelection;
        if (selectionChanged || ports.isEmpty) {
          _connected = false;
          _resetDeviceInfo();
        }
      });

      if (shouldDisconnect) {
        await _disconnectTransport();
      }

      _log(
        ports.isEmpty
            ? 'No serial ports detected'
            : 'Detected ${ports.length} serial port(s)',
        level: ports.isEmpty ? LogLevel.warning : LogLevel.info,
      );
    } on SerialError catch (error) {
      final pluginUnavailable = error.type == SerialErrorType.platformUnavailable;
      final shouldDisconnect = _transport.isOpen;

      if (mounted) {
        setState(() {
          _serialPluginAvailable = !pluginUnavailable ? true : false;
          _serialStatusMessage = pluginUnavailable
              ? _t('serialPluginUnavailable')
              : error.message;
          _availablePorts = const <SerialPortInfo>[];
          _selectedPortName = null;
          _connected = false;
          _resetDeviceInfo();
        });
      }

      if (shouldDisconnect) {
        await _disconnectTransport();
      }

      _log(
        pluginUnavailable
            ? 'Serial plugin unavailable: ${error.message}'
            : 'Failed to load serial ports: ${error.message}',
        level: pluginUnavailable ? LogLevel.warning : LogLevel.error,
      );
    } catch (error) {
      final shouldDisconnect = _transport.isOpen;

      if (mounted) {
        setState(() {
          _serialPluginAvailable = false;
          _serialStatusMessage = _t('serialPluginUnavailable');
          _availablePorts = const <SerialPortInfo>[];
          _selectedPortName = null;
          _connected = false;
          _resetDeviceInfo();
        });
      }

      if (shouldDisconnect) {
        await _disconnectTransport();
      }

      _log('Unexpected serial port error: $error', level: LogLevel.error);
    } finally {
      if (mounted) {
        setState(() => _loadingPorts = false);
      }
    }
  }

  Future<void> _selectPort(String portName) async {
    if (_selectedPortName == portName) {
      return;
    }

    final wasOpen = _transport.isOpen;
    if (wasOpen) {
      await _disconnectTransport();
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPortName = portName;
      _connected = false;
      _resetDeviceInfo();
    });
    _log('Selected serial port: $portName');
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
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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
    if (!mounted) {
      return;
    }
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
    _log(_t('sampleFlashNotice'), level: LogLevel.warning);
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

  Widget _buildLanguageChip(Locale locale) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Image.asset(
            AppStrings.languageFlagAsset(locale),
            width: 22,
            height: 16,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.flag_rounded,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(AppStrings.languageDisplayName(locale)),
      ],
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
                  .map(_buildLanguageChip)
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
                      child: _buildLanguageChip(locale),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Icon(Icons.usb_rounded),
                    ),
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
                              hint: Text(
                                _serialPluginAvailable
                                    ? t('noSerialPorts')
                                    : t('serialUnavailable'),
                              ),
                              value: _selectedPortName,
                              onChanged: !_serialPluginAvailable ||
                                      _availablePorts.isEmpty
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        _selectPort(value);
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
                          if (_serialStatusMessage != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _serialStatusMessage!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _serialPluginAvailable
                                        ? Colors.amber.shade800
                                        : Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          ],
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
                FilledButton(
                  onPressed: _canConnect ? _connect : null,
                  child: Text(t('connect')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _detectChip : null,
                  child: Text(t('detectChip')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _readMac : null,
                  child: Text(t('readMac')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _flashInfo : null,
                  child: Text(t('flashInfo')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _writeFlash : null,
                  child: Text(t('writeFlash')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _eraseFlash : null,
                  child: Text(t('eraseFlash')),
                ),
                FilledButton.tonal(
                  onPressed: _connected ? _readMd5 : null,
                  child: Text(t('readMd5')),
                ),
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
