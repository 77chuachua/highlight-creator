import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:highlight_creator/data/l10n.dart';

/// Explains how to install the Windows speech packs that the voice list draws
/// from, and offers to open the right Settings page.
Future<void> openVoicePackGuideDialog(
  BuildContext context, {
  VoidCallback? onRefresh,
  String? warning,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        VoicePackGuideDialog(onRefresh: onRefresh, warning: warning),
  );
}

class VoicePackGuideDialog extends ConsumerWidget {
  /// Called after the user is sent to Settings, so the caller can reload the
  /// voice list when they come back.
  final VoidCallback? onRefresh;

  /// Shown first when the dialog was opened because something was missing
  /// (no plugin, no studio) rather than by the user asking about voices.
  final String? warning;

  VoicePackGuideDialog({super.key, this.onRefresh, this.warning});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = ref.watch(l10nProvider);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.record_voice_over_outlined, size: 20),
          SizedBox(width: 8),
          Text(l10n.voiceGuideTitle),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (warning != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withAlpha(28),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: theme.colorScheme.error.withAlpha(70)),
                  ),
                  child: Text(
                    warning!,
                    style:
                        TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ),
                SizedBox(height: 12),
              ],
              Text(
                l10n.voiceGuideIntro,
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: 14),
              _step(
                theme,
                '1',
                l10n.voiceGuideStep1,
              ),
              SizedBox(height: 8),
              _step(
                theme,
                '2',
                l10n.voiceGuideStep2,
              ),
              SizedBox(height: 12),
              Text(
                l10n.voiceGuideAfter,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: 14),
              Divider(height: 1, color: Colors.white12),
              SizedBox(height: 14),
              Text(l10n.voiceGuideOwnTitle, style: theme.textTheme.titleSmall),
              SizedBox(height: 6),
              Text(
                '${l10n.voiceGuideOwnBody} ${l10n.voiceGuideOwnImport}',
                style: theme.textTheme.bodyMedium,
              ),
              SizedBox(height: 10),
              Text(
                l10n.voiceGuideEngine,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _openSettings('ms-settings:easeofaccess-narrator'),
          icon: Icon(Icons.open_in_new, size: 16),
          label: Text(l10n.voiceGuideNarrator),
        ),
        TextButton.icon(
          onPressed: () => _openSettings('ms-settings:regionlanguage'),
          icon: Icon(Icons.open_in_new, size: 16),
          label: Text(l10n.voiceGuideLanguage),
        ),
        if (onRefresh != null)
          TextButton.icon(
            onPressed: () {
              onRefresh!();
              Navigator.of(context).pop();
            },
            icon: Icon(Icons.refresh, size: 16),
            label: Text(l10n.commonRefresh),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonGotIt),
        ),
      ],
    );
  }

  Widget _step(ThemeData theme, String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primaryContainer,
          ),
          child: Text(number, style: const TextStyle(fontSize: 11, height: 1)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  /// Hand a settings URI to the shell; Windows opens the matching page.
  void _openSettings(String uri) {
    try {
      Process.start('cmd', ['/c', 'start', '', uri], runInShell: true);
    } catch (_) {
      // Nothing to do: the user can paste the path into Settings themselves.
    }
  }
}
