import 'package:flutter/material.dart';
import 'package:highlight_creator/data/l10n.dart';

/// One entry of the supported-hotkeys table. `combo` is the raw key combo
/// (e.g. 'Ctrl + M'); `label` is already localized.
class HotkeyDef {
  final String combo;
  final String label;
  const HotkeyDef(this.label, this.combo);
}

/// Single source of truth for the app hotkeys — shared by the settings
/// dialog list and the key handler in MainWindow.
List<HotkeyDef> hotkeyDefs(AppStrings l10n) => [
      HotkeyDef(l10n.hotkeyNameMark, 'Ctrl + M'),
      HotkeyDef(l10n.hotkeyNameSeekBack, 'Ctrl + \u2190'),
      HotkeyDef(l10n.hotkeyNameSeekForward, 'Ctrl + \u2192'),
      HotkeyDef(l10n.hotkeyNamePlayPause, 'Space'),
      HotkeyDef(l10n.hotkeyNameGoTo, 'Ctrl + G'),
      HotkeyDef(l10n.hotkeyNameSave, 'Ctrl + S'),
      HotkeyDef(l10n.hotkeyNameNew, 'Ctrl + N'),
      HotkeyDef(l10n.hotkeyNameOpen, 'Ctrl + O'),
      HotkeyDef(l10n.hotkeyNameClose, 'Ctrl + Q'),
      HotkeyDef(l10n.hotkeyNameAddSource, 'Ctrl + A'),
      HotkeyDef(l10n.hotkeyNameTemplates, 'Ctrl + T'),
    ];

/// Modal listing every supported hotkey (issues.md: settings → hotkeys).
class HotkeysDialog extends StatelessWidget {
  final AppStrings l10n;
  const HotkeysDialog({super.key, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final defs = hotkeyDefs(l10n);
    return AlertDialog(
      key: const Key('hotkeys_dialog'),
      title: Row(
        children: [
          Icon(Icons.keyboard, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(l10n.hotkeyTitle),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: defs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(defs[i].label)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    defs[i].combo,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
