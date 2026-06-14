// Copyright (c) 2026 Piergiorgio Vagnozzi.
// Licensed under the MIT License.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization/app_localizations.dart';
import 'theme/app_theme.dart';
import 'ui/serial_terminal_page.dart';
import 'ui/splash_screen.dart';

class SerialTerminalApp extends StatefulWidget {
  const SerialTerminalApp({super.key});

  @override
  State<SerialTerminalApp> createState() => _SerialTerminalAppState();
}

class _SerialTerminalAppState extends State<SerialTerminalApp> {
  Locale? _locale;
  bool _showSplash = true;
  Timer? _splashTimer;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  void _onLocaleChanged(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  void _onThemeModeChanged(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Platform Serial Terminal',
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: _showSplash
          ? const SplashScreen()
          : SerialTerminalPage(
              currentLocale: _locale,
              onLocaleChanged: _onLocaleChanged,
              onThemeModeChanged: _onThemeModeChanged,
              currentThemeMode: _themeMode,
            ),
    );
  }
}
