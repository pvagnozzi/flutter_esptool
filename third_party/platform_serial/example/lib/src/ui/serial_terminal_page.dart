// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'package:flutter/material.dart';
import 'package:platform_serial/platform_serial.dart';

import '../localization/app_localizations.dart';
import '../models/terminal_entry.dart';
import '../services/serial_terminal_controller.dart';
import '../widgets/app_logo.dart';

class SerialTerminalPage extends StatefulWidget {
  const SerialTerminalPage({
    super.key,
    this.controller,
    required this.onLocaleChanged,
    required this.currentLocale,
    required this.onThemeModeChanged,
    required this.currentThemeMode,
  });

  final SerialTerminalController? controller;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale? currentLocale;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode currentThemeMode;

  @override
  State<SerialTerminalPage> createState() => _SerialTerminalPageState();
}

class _SerialTerminalPageState extends State<SerialTerminalPage> {
  late final SerialTerminalController _controller;
  late final bool _ownsController;

  String? _selectedPort;
  final TextEditingController _baudController =
      TextEditingController(text: '115200');
  final TextEditingController _readTimeoutController =
      TextEditingController(text: '5000');
  final TextEditingController _writeTimeoutController =
      TextEditingController(text: '5000');
  final TextEditingController _txController = TextEditingController();

  int _dataBits = 8;
  SerialStopBits _stopBits = SerialStopBits.one;
  SerialParity _parity = SerialParity.none;
  SerialFlowControl _flowControl = SerialFlowControl.none;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SerialTerminalController();
    _ownsController = widget.controller == null;
    _controller.addListener(_onControllerChanged);
    _controller.refreshPorts();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    _baudController.dispose();
    _readTimeoutController.dispose();
    _writeTimeoutController.dispose();
    _txController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    if (_selectedPort != null &&
        !_controller.availablePorts
            .map((SerialPortInfo item) => item.portName)
            .contains(_selectedPort)) {
      _selectedPort = null;
    }
    setState(() {});
  }

  Future<void> _openConnection(AppLocalizations t) async {
    if (_selectedPort == null) {
      _showSnack(t.noPorts);
      return;
    }
    try {
      await _controller.open(
        SerialConfig(
          portName: _selectedPort!,
          baudRate: int.tryParse(_baudController.text) ?? 115200,
          dataBits: _dataBits,
          stopBits: _stopBits,
          parity: _parity,
          flowControl: _flowControl,
          readTimeout: Duration(
              milliseconds: int.tryParse(_readTimeoutController.text) ?? 5000),
          writeTimeout: Duration(
              milliseconds: int.tryParse(_writeTimeoutController.text) ?? 5000),
        ),
      );
    } catch (_) {
      _showSnack(t.openingFailed);
    }
  }

  Future<void> _closeConnection(AppLocalizations t) async {
    try {
      await _controller.close();
    } catch (_) {
      _showSnack(t.closingFailed);
    }
  }

  Future<void> _send(AppLocalizations t) async {
    final String payload = _txController.text.trim();
    if (payload.isEmpty) {
      return;
    }
    try {
      await _controller.sendText(payload);
      _txController.clear();
    } catch (_) {
      _showSnack(t.sendFailed);
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAboutDialog(AppLocalizations t) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          icon: const AppLogo(size: 42),
          title: Text(t.about),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(t.appTitle),
              const SizedBox(height: 8),
              Text(t.appDescription),
              const SizedBox(height: 8),
              Text(t.copyright),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(context).pop();
                showLicensePage(
                  context: this.context,
                  applicationName: t.appTitle,
                  applicationVersion: '1.0.0',
                );
              },
              child: Text(t.licenses),
            ),
          ],
        );
      },
    );
  }

  IconData _getThemeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
      ThemeMode.system => Icons.brightness_auto,
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations t = AppLocalizations.of(context);
    final bool isRtl = t.isRtl;
    final List<DropdownMenuItem<String>> ports =
        _controller.availablePorts.map((SerialPortInfo info) {
      return DropdownMenuItem<String>(
        value: info.portName,
        child: Text('${info.portName} • ${info.description}'),
      );
    }).toList(growable: false);

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.appTitle),
          actions: <Widget>[
            PopupMenuButton<ThemeMode>(
              tooltip: 'Theme',
              icon: Icon(_getThemeIcon(widget.currentThemeMode)),
              onSelected: widget.onThemeModeChanged,
              itemBuilder: (BuildContext context) {
                return <PopupMenuEntry<ThemeMode>>[
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.light_mode),
                        SizedBox(width: 12),
                        Text('Light'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.dark_mode),
                        SizedBox(width: 12),
                        Text('Dark'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.brightness_auto),
                        SizedBox(width: 12),
                        Text('System'),
                      ],
                    ),
                  ),
                ];
              },
            ),
            PopupMenuButton<Locale>(
              tooltip: t.chooseLanguage,
              icon: const Icon(Icons.language),
              onSelected: widget.onLocaleChanged,
              itemBuilder: (BuildContext context) {
                return AppLocalizations.supportedLocales.map((Locale locale) {
                  final String flag =
                      AppLocalizations.localeFlags[locale.languageCode] ?? '';
                  final String label =
                      AppLocalizations.localeLabels[locale.languageCode] ??
                          locale.languageCode;
                  return PopupMenuItem<Locale>(
                    value: locale,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(flag),
                        const SizedBox(width: 12),
                        Text(label),
                      ],
                    ),
                  );
                }).toList(growable: false);
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: t.about,
              onPressed: () => _showAboutDialog(t),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                t.serialParameters,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              onPressed: _controller.isBusy
                                  ? null
                                  : _controller.refreshPorts,
                              icon: const Icon(Icons.refresh),
                              tooltip: t.refreshPorts,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: ports.any(
                                        (DropdownMenuItem<String> item) =>
                                            item.value == _selectedPort)
                                    ? _selectedPort
                                    : null,
                                items: ports,
                                onChanged: (String? value) {
                                  setState(() {
                                    _selectedPort = value;
                                  });
                                },
                                decoration: InputDecoration(labelText: t.port),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _baudController,
                                keyboardType: TextInputType.number,
                                decoration:
                                    InputDecoration(labelText: t.baudRate),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: _dataBits,
                                items: const <DropdownMenuItem<int>>[
                                  DropdownMenuItem<int>(
                                      value: 5, child: Text('5')),
                                  DropdownMenuItem<int>(
                                      value: 6, child: Text('6')),
                                  DropdownMenuItem<int>(
                                      value: 7, child: Text('7')),
                                  DropdownMenuItem<int>(
                                      value: 8, child: Text('8')),
                                ],
                                onChanged: (int? value) {
                                  if (value != null) {
                                    setState(() {
                                      _dataBits = value;
                                    });
                                  }
                                },
                                decoration:
                                    InputDecoration(labelText: t.dataBits),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<SerialStopBits>(
                                initialValue: _stopBits,
                                items: SerialStopBits.values
                                    .map((SerialStopBits value) {
                                  return DropdownMenuItem<SerialStopBits>(
                                    value: value,
                                    child: Text(value.name),
                                  );
                                }).toList(growable: false),
                                onChanged: (SerialStopBits? value) {
                                  if (value != null) {
                                    setState(() {
                                      _stopBits = value;
                                    });
                                  }
                                },
                                decoration:
                                    InputDecoration(labelText: t.stopBits),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DropdownButtonFormField<SerialParity>(
                                initialValue: _parity,
                                items: SerialParity.values
                                    .map((SerialParity value) {
                                  return DropdownMenuItem<SerialParity>(
                                    value: value,
                                    child: Text(value.name),
                                  );
                                }).toList(growable: false),
                                onChanged: (SerialParity? value) {
                                  if (value != null) {
                                    setState(() {
                                      _parity = value;
                                    });
                                  }
                                },
                                decoration:
                                    InputDecoration(labelText: t.parity),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<SerialFlowControl>(
                                initialValue: _flowControl,
                                items: SerialFlowControl.values
                                    .map((SerialFlowControl value) {
                                  return DropdownMenuItem<SerialFlowControl>(
                                    value: value,
                                    child: Text(value.name),
                                  );
                                }).toList(growable: false),
                                onChanged: (SerialFlowControl? value) {
                                  if (value != null) {
                                    setState(() {
                                      _flowControl = value;
                                    });
                                  }
                                },
                                decoration:
                                    InputDecoration(labelText: t.flowControl),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: _readTimeoutController,
                                keyboardType: TextInputType.number,
                                decoration:
                                    InputDecoration(labelText: t.readTimeoutMs),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _writeTimeoutController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    labelText: t.writeTimeoutMs),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            FilledButton.icon(
                              onPressed: _controller.isBusy
                                  ? null
                                  : () => _openConnection(t),
                              icon: const Icon(Icons.usb),
                              label: Text(t.open),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: (!_controller.isBusy &&
                                      _controller.isConnected)
                                  ? () => _closeConnection(t)
                                  : null,
                              icon: const Icon(Icons.link_off),
                              label: Text(t.close),
                            ),
                            OutlinedButton.icon(
                              onPressed: _controller.clearTerminal,
                              icon:
                                  const Icon(Icons.cleaning_services_outlined),
                              label: Text(t.clear),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _controller.isConnected
                              ? t.connectedTo(
                                  _controller.connectedPortName ?? '-')
                              : t.disconnected,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: _controller.isConnected
                                        ? Colors.green
                                        : Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            t.terminal,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _buildTerminalList(context, t),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _txController,
                                  enabled: _controller.isConnected,
                                  onSubmitted: (_) => _send(t),
                                  decoration: InputDecoration(
                                    hintText: t.inputPlaceholder,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: _controller.isConnected
                                    ? () => _send(t)
                                    : null,
                                child: Text(t.send),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTerminalList(BuildContext context, AppLocalizations t) {
    if (_controller.entries.isEmpty) {
      return Center(
        child: Text(
          t.disconnected,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.builder(
      itemCount: _controller.entries.length,
      itemBuilder: (BuildContext context, int index) {
        final TerminalEntry entry = _controller.entries[index];
        final String timestamp =
            '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
            '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
            '${entry.timestamp.second.toString().padLeft(2, '0')}';
        final _EntryStyle style = _styleFor(context, entry.type, t);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: style.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '[$timestamp] ${style.label}: ${entry.message}',
            style: TextStyle(color: style.foreground),
          ),
        );
      },
    );
  }

  _EntryStyle _styleFor(
    BuildContext context,
    TerminalEntryType type,
    AppLocalizations t,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (type) {
      case TerminalEntryType.incoming:
        return _EntryStyle(
          label: t.incoming,
          background: Colors.green.withValues(alpha: 0.15),
          foreground: scheme.onSurface,
        );
      case TerminalEntryType.outgoing:
        return _EntryStyle(
          label: t.outgoing,
          background: Colors.blue.withValues(alpha: 0.15),
          foreground: scheme.onSurface,
        );
      case TerminalEntryType.system:
        return _EntryStyle(
          label: t.system,
          background: Colors.orange.withValues(alpha: 0.14),
          foreground: scheme.onSurface,
        );
      case TerminalEntryType.error:
        return _EntryStyle(
          label: t.error,
          background: scheme.errorContainer,
          foreground: scheme.onErrorContainer,
        );
    }
  }
}

class _EntryStyle {
  const _EntryStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;
}
