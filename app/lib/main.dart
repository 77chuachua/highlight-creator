import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/main_window.dart';
import 'package:highlight_creator/services/error_logger.dart';

final windowManager = WindowManager.instance;

class ThemeModeNotifier extends StateNotifier<String> {
  final SettingsService _svc;
  ThemeModeNotifier(this._svc) : super('dark') {
    _load();
  }
  Future<void> _load() async {
    final t = await _svc.themeMode;
    if (mounted) state = t;
  }
  Future<void> setTheme(String t) async {
    state = t;
    await _svc.setThemeMode(t);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, String>(
    (ref) => ThemeModeNotifier(ref.watch(settingsServiceProvider)));

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Capture everything uncaught into the daily error log (services/error_logger).
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      ErrorLogger.log(details.exception, details.stack, source: 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      ErrorLogger.log(error, stack, source: 'platform');
      return true;
    };

    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();

    unawaited(windowManager.setPreventClose(true));

    // Initialize DI gracefully — fall back to in-memory DB if file DB fails.
    try {
      await initializeDependencies();
    } catch (e, st) {
      debugPrint('initializeDependencies failed: $e');
      ErrorLogger.log(e, st, source: 'init');
      await initializeDependenciesFallback();
    }

    runApp(
      ProviderScope(
        overrides: [
          // Real autosave cadence: refresh today's project file every 30s.
          autoSaveIntervalProvider.overrideWithValue(const Duration(seconds: 30)),
        ],
        child: const HighlightCreatorApp(),
      ),
    );
  }, (error, stack) => ErrorLogger.log(error, stack, source: 'zone'));
}

class HighlightCreatorApp extends ConsumerWidget {
  const HighlightCreatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Highlight Creator',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode == 'light' ? ThemeMode.light : ThemeMode.dark,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        focusColor: const Color(0xFF6C63FF).withAlpha(120),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        cardColor: const Color(0xFF1A1A2E),
        focusColor: const Color(0xFF6C63FF).withAlpha(120),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(const Color(0xFF1A1A2E)),
          ),
        ),
      ),
      home: const MainWindow(),
    );
  }
}
