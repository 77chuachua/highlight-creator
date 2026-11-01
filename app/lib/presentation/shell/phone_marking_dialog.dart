import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/services/phone_marking_server.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// One app-wide server: closing the dialog must leave it listening, so the
/// dialog only starts it and the user stops it explicitly.
final phoneMarkingServerProvider = Provider<PhoneMarkingServer>((ref) {
  final server = PhoneMarkingServer(
    sources: () =>
        ref.read(recordProvider).selectedProject?.sources ??
        const <VideoSource>[],
    strings: () => ref.read(l10nProvider),
  );
  ref.onDispose(() => unawaited(server.stop()));
  return server;
});

/// QR + address + token for docs/phone_marking.md step 1.
class PhoneMarkingDialog extends ConsumerStatefulWidget {
  const PhoneMarkingDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const PhoneMarkingDialog(),
    );
  }

  @override
  ConsumerState<PhoneMarkingDialog> createState() => _PhoneMarkingDialogState();
}

class _PhoneMarkingDialogState extends ConsumerState<PhoneMarkingDialog> {
  bool _busy = false;
  String? _error;

  PhoneMarkingServer get _server => ref.read(phoneMarkingServerProvider);

  @override
  void initState() {
    super.initState();
    // Opening the dialog starts the server; closing it does not stop it.
    if (!_server.isRunning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_start());
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _server.start();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = '${ref.read(l10nProvider).phoneMarkingStartFailed}$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _server.stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final theme = Theme.of(context);
    final running = _server.isRunning;
    final url = _server.url;
    final sources = ref.watch(recordProvider).selectedProject?.sources ??
        const <VideoSource>[];

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.qr_code_2, size: 20),
          const SizedBox(width: 8),
          Text(l10n.phoneMarkingTitle),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.phoneMarkingFirewallHint,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _QrBox(url: url, scan: l10n.phoneMarkingScan),
              const SizedBox(height: 12),
              _InfoRow(
                label: l10n.phoneMarkingAddress,
                value: _server.baseUrl ?? '—',
              ),
              _InfoRow(
                label: l10n.phoneMarkingToken,
                value: running ? _server.token : '—',
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    size: 14,
                    color: running ? Colors.green : theme.disabledColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    running
                        ? l10n.phoneMarkingRunning
                        : l10n.phoneMarkingStopped,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (running && _server.lanAddress == null) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.phoneMarkingLocalhostHint,
                  style:
                      TextStyle(fontSize: 11, color: theme.colorScheme.error),
                ),
              ],
              if (sources.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.phoneMarkingNoSources,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style:
                      TextStyle(fontSize: 11, color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        FilledButton(
          onPressed: _busy ? null : (running ? _stop : _start),
          child: Text(running ? l10n.phoneMarkingStop : l10n.phoneMarkingOpen),
        ),
      ],
    );
  }
}

class _QrBox extends StatelessWidget {
  final String? url;
  final String scan;

  const _QrBox({required this.url, required this.scan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 208,
          height: 208,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: url == null
              ? const Icon(Icons.qr_code_2, size: 64, color: Colors.black26)
              : QrImageView(
                  data: url!,
                  size: 192,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  semanticsLabel: scan,
                ),
        ),
        if (url != null) ...[
          const SizedBox(height: 6),
          Text(scan, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
