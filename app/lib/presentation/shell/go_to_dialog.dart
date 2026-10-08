import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

/// Parse an `hh:mm:ss` (1–3 colon-separated parts) string into a [Duration].
/// Returns null for malformed input (non-numeric, negative, bad m/s range).
Duration? parseHms(String raw) {
  final parts = raw.trim().split(':');
  if (parts.isEmpty || parts.length > 3) return null;
  final nums = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null || v < 0) return null;
    nums.add(v);
  }
  while (nums.length < 3) {
    nums.insert(0, 0); // "10:00" -> 0h 10m 00s
  }
  if (nums[1] > 59 || nums[2] > 59) return null;
  return Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
}

/// Build a [Duration] from three separate hh/mm/ss field strings. Empty
/// fields count as zero; null is returned for malformed input (non-numeric,
/// negative, or m/s outside 0–59).
Duration? parseHmsParts(String h, String m, String s) {
  int? toInt(String v, int max) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    final n = int.tryParse(t);
    return n != null && n >= 0 && n <= max ? n : null;
  }
  final hh = toInt(h, 1000000);
  final mm = toInt(m, 59);
  final ss = toInt(s, 59);
  if (hh == null || mm == null || ss == null) return null;
  return Duration(hours: hh, minutes: mm, seconds: ss);
}

/// Map a global offset (ms across all sources concatenated) to a
/// (sourceIndex, localMs) pair. Clamps to the last source when past the end.
(int, int) resolveGlobalSeek(List<int> durationsMs, int offsetMs) {
  if (durationsMs.isEmpty) return (0, 0);
  var rem = offsetMs < 0 ? 0 : offsetMs;
  for (var i = 0; i < durationsMs.length; i++) {
    final d = durationsMs[i];
    if (rem < d) return (i, rem);
    rem -= d;
  }
  return (durationsMs.length - 1, durationsMs.last);
}

/// Seek all project sources combined: resolve [target] against the
/// concatenated durations, load the matching source at the local offset and
/// start playing. Falls back to a single-source direct seek when durations
/// are unknown.
Future<bool> seekCombinedSources(
    BuildContext context, WidgetRef ref, Duration target) async {
  final l10n = ref.read(l10nProvider);
  final sources = ref.read(recordProvider).selectedProject?.sources ?? const [];
  if (sources.isEmpty) {
    _snack(context, l10n.gotoNoSource);
    return false;
  }
  final playerVm = ref.read(videoPlayerProvider.notifier);

  final normalized = target.isNegative ? Duration.zero : target;
  final allKnown = sources.every((s) => s.durationMs > 0);
  if (allKnown) {
    final durations = <int>[for (final s in sources) s.durationMs];
    final total = durations.fold<int>(0, (a, b) => a + b);
    var offsetMs = normalized.inMilliseconds;
    var clamped = false;
    if (offsetMs > total) {
      offsetMs = total;
      clamped = true;
    }
    final (index, localMs) = resolveGlobalSeek(durations, offsetMs);
    await playerVm.loadVideo(
      sources[index].filePath,
      initialPosition: Duration(milliseconds: localMs),
    );
    await playerVm.play();
    if (!context.mounted) return clamped;
    _snack(
        context,
        '${l10n.gotoSeeked}${_hms(normalized)}'
        '${clamped ? l10n.gotoClamped : ''}');
    return clamped;
  } else if (sources.length == 1) {
    // No duration metadata: seek directly inside the single source.
    await playerVm.loadVideo(
      sources.single.filePath,
      initialPosition: normalized,
    );
    await playerVm.play();
    if (!context.mounted) return false;
    _snack(context, '${l10n.gotoSeeked}${_hms(normalized)}');
    return false;
  }
  _snack(context, l10n.gotoNoSource);
  return false;
}

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

String _hms(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Open the Go-to dialog. `base` is optional and remembered across sessions.
/// `dest - base` (or `dest` when base is empty) is applied on the combined
/// source timeline, then the video seeks there and plays.
Future<void> openGoToDialog(BuildContext context, WidgetRef ref) async {
  final l10n = ref.read(l10nProvider);
  final svc = ref.read(settingsServiceProvider);
  final savedBase = await svc.gotoBaseTime;
  if (!context.mounted) return;

  final result = await showDialog<Duration?>(
    context: context,
    builder: (_) => GoToDialog(
      savedBase: savedBase ?? '',
      settings: svc,
      l10n: l10n,
    ),
  );
  if (result != null && context.mounted) {
    await seekCombinedSources(context, ref, result);
  }
}

/// Public Go-to dialog (parameterised so it is directly testable). Owns its
/// own controllers and offers three separate hh/mm/ss inputs per field group
/// (issues.md). `dest - base` (or `dest` when base is empty) is the result.
class GoToDialog extends StatefulWidget {
  final String savedBase;
  final SettingsService settings;
  final AppStrings l10n;

  const GoToDialog({
    super.key,
    required this.savedBase,
    required this.settings,
    required this.l10n,
  });

  @override
  State<GoToDialog> createState() => _GoToDialogState();
}

class _GoToDialogState extends State<GoToDialog> {
  String? _error;
  final _destH = TextEditingController();
  final _destM = TextEditingController();
  final _destS = TextEditingController();
  final _baseH = TextEditingController();
  final _baseM = TextEditingController();
  final _baseS = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prefill the base-time fields from the remembered 'hh:mm:ss' value.
    final saved = parseHms(widget.savedBase);
    if (saved != null) {
      _baseH.text = '${saved.inHours}';
      _baseM.text = '${saved.inMinutes.remainder(60)}';
      _baseS.text = '${saved.inSeconds.remainder(60)}';
    }
  }

  @override
  void dispose() {
    for (final c in [_destH, _destM, _destS, _baseH, _baseM, _baseS]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _allEmpty(TextEditingController h, TextEditingController m,
          TextEditingController s) =>
      h.text.trim().isEmpty && m.text.trim().isEmpty && s.text.trim().isEmpty;

  void _go() {
    final l10n = widget.l10n;
    if (_allEmpty(_destH, _destM, _destS)) {
      setState(() => _error = l10n.gotoBadTime);
      return;
    }
    final dest = parseHmsParts(_destH.text, _destM.text, _destS.text);
    if (dest == null) {
      setState(() => _error = l10n.gotoBadTime);
      return;
    }
    Duration? base;
    if (!_allEmpty(_baseH, _baseM, _baseS)) {
      base = parseHmsParts(_baseH.text, _baseM.text, _baseS.text);
      if (base == null) {
        setState(() => _error = l10n.gotoBadTime);
        return;
      }
    }
    // Remember base time if it changed (issues.md); store '' when cleared.
    final baseText = base == null ? '' : _hms(base);
    if (baseText != widget.savedBase) {
      widget.settings.setGotoBaseTime(baseText);
    }
    var offset = base == null ? dest : dest - base;
    if (offset.isNegative) offset = Duration.zero;
    Navigator.pop(context, offset);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return AlertDialog(
      key: const Key('goto_dialog'),
      title: Text(l10n.gotoTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.gotoDestTime, style: labelStyle),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HmsField(
                fieldKey: const Key('goto_dest_h'),
                controller: _destH,
                label: 'hh',
                autofocus: true,
              ),
              const _Colon(),
              _HmsField(
                fieldKey: const Key('goto_dest_m'),
                controller: _destM,
                label: 'mm',
              ),
              const _Colon(),
              _HmsField(
                fieldKey: const Key('goto_dest_s'),
                controller: _destS,
                label: 'ss',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.gotoBaseTime, style: labelStyle),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HmsField(
                fieldKey: const Key('goto_base_h'),
                controller: _baseH,
                label: 'hh',
              ),
              const _Colon(),
              _HmsField(
                fieldKey: const Key('goto_base_m'),
                controller: _baseM,
                label: 'mm',
              ),
              const _Colon(),
              _HmsField(
                fieldKey: const Key('goto_base_s'),
                controller: _baseS,
                label: 'ss',
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('goto_go'),
          onPressed: _go,
          child: Text(l10n.gotoGo),
        ),
      ],
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(':'),
    );
  }
}

class _HmsField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final bool autofocus;

  const _HmsField({
    this.fieldKey,
    required this.controller,
    required this.label,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: TextField(
        key: fieldKey,
        controller: controller,
        autofocus: autofocus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        ),
      ),
    );
  }
}
