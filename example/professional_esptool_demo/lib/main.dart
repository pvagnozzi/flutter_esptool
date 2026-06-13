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
  late final _ScriptedTransport _transport;
  late final ConnectionService _connectionService;
  late final ChipDetectionService _chipDetectionService;
  late final InfoService _infoService;
  late final FlashService _flashService;

  final List<String> _logs = <String>[];
  bool _connected = false;
  String _chip = '-';
  String _mac = '-';
  String _flash = '-';

  @override
  void initState() {
    super.initState();
    _transport = _ScriptedTransport();
    _connectionService = ConnectionService(_transport);
    _chipDetectionService = ChipDetectionService(_transport);
    _infoService = InfoService(
        transport: _transport, chipDetectionService: _chipDetectionService);
    _flashService = FlashService(transport: _transport);
  }

  void _log(String message) {
    setState(() => _logs.insert(0, message));
  }

  Future<void> _connect() async {
    final result =
        await _connectionService.connect(const EspConfig(portName: 'DEMO-COM'));
    result.fold(
      (_) {
        setState(() => _connected = true);
        _log('Connection successful');
      },
      (error) => _log('Connection failed: ${error.message}'),
    );
  }

  Future<void> _detectChip() async {
    final result = await _chipDetectionService.detect();
    result.fold(
      (chip) {
        setState(() => _chip = chip.description);
        _log('Chip detected: ${chip.description}');
      },
      (error) => _log('Chip detection failed: ${error.message}'),
    );
  }

  Future<void> _readMac() async {
    final result = await _infoService.getMac();
    result.fold(
      (mac) {
        setState(() => _mac = mac);
        _log('MAC: $mac');
      },
      (error) => _log('MAC read failed: ${error.message}'),
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
      (error) => _log('Flash info failed: ${error.message}'),
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
      (error) => _log('Flash write failed: ${error.message}'),
    );
  }

  Future<void> _eraseFlash() async {
    final result = await _flashService.eraseFlash();
    result.fold(
      (_) => _log('Flash erase completed'),
      (error) => _log('Flash erase failed: ${error.message}'),
    );
  }

  Future<void> _readMd5() async {
    final result = await _flashService.md5Flash(0x1000, 4096);
    result.fold(
      (hash) => _log('Device MD5: $hash'),
      (error) => _log('MD5 failed: ${error.message}'),
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
              onChanged: (value) {
                if (value != null) {
                  widget.onLocaleChanged(value);
                }
              },
              items: AppStrings.supportedLocales
                  .map(
                    (locale) => DropdownMenuItem(
                      value: locale,
                      child: Text(locale.languageCode.toUpperCase()),
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
                const DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                    value: ThemeMode.light, child: Text(t('light'))),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(t('dark'))),
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
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.chevron_right_rounded),
                    title: Text(_logs[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptedTransport implements EspTransportInterface {
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
    final queue = _responses[command.opcode];
    if (queue == null || queue.isEmpty) {
      return _ok(command.opcode);
    }
    return queue.removeFirst();
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
}
