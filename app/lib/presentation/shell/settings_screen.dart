import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/main.dart' show themeModeProvider;
import 'package:highlight_creator/presentation/shell/guide_dialog.dart';
import 'package:highlight_creator/presentation/shell/hotkeys.dart';

/// User profile and settings screen (Phase 4).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _languages = ['English', '中文'];

  String _s(String zh, String en) => ref.read(languageProvider) == '中文' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final lang = ref.watch(languageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            l10n.settingsTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SectionHeader(title: _s('主题', 'Theme')),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: Text(_s('主题', 'Theme')),
                subtitle: Text(ref.watch(themeModeProvider) == 'light' ? _s('浅色', 'Light') : _s('深色', 'Dark')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickTheme,
              ),
              const Divider(),
              _SectionHeader(title: l10n.languageSection),
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(l10n.languageLabel),
                subtitle: Text(lang),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickLanguage(l10n),
              ),
              const Divider(),
              _SectionHeader(title: l10n.hotkeySection),
              ListTile(
                leading: const Icon(Icons.keyboard),
                title: Text(l10n.hotkeyTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => HotkeysDialog(l10n: ref.read(l10nProvider)),
                ),
              ),
              const Divider(),
              _SectionHeader(title: l10n.helpSection),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(l10n.guideTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => const GuideDialog(),
                  );
                },
              ),
              const Divider(),
              _SectionHeader(title: l10n.aboutSection),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.appName),
                subtitle: Text(l10n.appVersionInfo),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _pickLanguage(AppStrings l10n) {
    final langNotifier = ref.read(languageProvider.notifier);
    final currentLang = ref.read(languageProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.selectLanguage),
        content: RadioGroup<String>(
          groupValue: currentLang,
          onChanged: (v) {
            if (v != null) {
              langNotifier.setLanguage(v);
              Navigator.pop(ctx);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _languages
                .map((lang) => RadioListTile<String>(
                      title: Text(lang),
                      value: lang,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _pickTheme() {
    final currentTheme = ref.read(themeModeProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_s('选择主题', 'Select Theme')),
        content: RadioGroup<String>(
          groupValue: currentTheme,
          onChanged: (v) {
            if (v != null) {
              ref.read(themeModeProvider.notifier).setTheme(v);
              Navigator.pop(ctx);
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: Text(_s('深色', 'Dark')),
                value: 'dark',
              ),
              RadioListTile<String>(
                title: Text(_s('浅色', 'Light')),
                value: 'light',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              )),
    );
  }
}
