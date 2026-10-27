import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/cache_catalog.dart';
import 'package:highlight_creator/services/error_logger.dart';

/// The caches this app writes to, all of them rebuildable.
///
/// Every entry can be opened in Explorer and cleared; clearing goes through
/// the recycle bin, so a wrong click costs nothing. Deliverables are excluded
/// on purpose: `results\final.mp4`, the reels in `results\best5`, the owned
/// clips in `5best_clips` and the project autosaves are never listed.
class CacheDialog extends ConsumerStatefulWidget {
  const CacheDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CacheDialog(),
    );
  }

  @override
  ConsumerState<CacheDialog> createState() => _CacheDialogState();
}

class _CacheRow {
  final String name;
  final String what;
  final String open;
  final List<File> Function() files;

  _CacheRow(this.name, this.what, this.open, this.files);
}

class _CacheDialogState extends ConsumerState<CacheDialog> {
  /// Strings for the current language; `ref` comes from ConsumerState.
  AppStrings get l10n => ref.read(l10nProvider);

  late final List<_CacheRow> _rows;
  late final List<int> _sizes;
  late final List<int> _counts;
  final Set<int> _busy = <int>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _rows = _buildRows();
    _sizes = List<int>.filled(_rows.length, 0);
    _counts = List<int>.filled(_rows.length, 0);
    _refresh();
  }

  List<_CacheRow> _buildRows() {
    final sep = Platform.pathSeparator;
    final temp = AppPaths.tempDir;
    return [
      _CacheRow(
        l10n.cacheSlicesName,
        l10n.cacheSlicesWhat,
        '$temp$sep' '5best_slices',
        () => _under('$temp$sep' '5best_slices'),
      ),
      _CacheRow(
        l10n.cacheNarrationName,
        l10n.cacheNarrationWhat,
        '$temp$sep' '5best_narration',
        () => _under('$temp$sep' '5best_narration'),
      ),
      _CacheRow(
        l10n.cacheWorkName,
        l10n.cacheWorkWhat,
        '$temp$sep' 'top5_work',
        () => _under('$temp$sep' 'top5_work', recursive: true),
      ),
      _CacheRow(
        l10n.cacheTemplatesName,
        l10n.cacheTemplatesWhat,
        AppPaths.templatesDir,
        () => _under(AppPaths.templatesDir),
      ),
      _CacheRow(
        l10n.cacheMakeName,
        l10n.cacheMakeWhat,
        AppPaths.resultsDir,
        // Deliberately not `final.mp4`: that is what Make produces, and you may
        // still want it.
        () => _under(AppPaths.resultsDir, name: isMakeIntermediate),
      ),
    ];
  }

  /// Files under [dir]; [name] filters by file name.
  static List<File> _under(String dir,
      {bool recursive = false, bool Function(String)? name}) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(recursive: recursive)
        .whereType<File>()
        .where((f) => name == null || name(f.uri.pathSegments.last))
        .toList();
  }

  /// Re-measure every row in one pass, then publish one frame.
  void _refresh() {
    final counts = <int>[];
    final sizes = <int>[];
    for (final row in _rows) {
      var count = 0;
      var total = 0;
      for (final f in row.files()) {
        try {
          total += f.lengthSync();
          count++;
        } catch (_) {
          // A file can vanish while we size it; leave it out of the total.
        }
      }
      counts.add(count);
      sizes.add(total);
    }
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        _counts[i] = counts[i];
        _sizes[i] = sizes[i];
      }
    });
  }

  /// Re-measure one row after clearing it.
  void _measure(int index) {
    var count = 0;
    var total = 0;
    for (final f in _rows[index].files()) {
      try {
        total += f.lengthSync();
        count++;
      } catch (_) {
        // A file can vanish while we size it; leave it out of the total.
      }
    }
    if (!mounted) return;
    setState(() {
      _counts[index] = count;
      _sizes[index] = total;
    });
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  void _open(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    Process.run('explorer', [dir.path], runInShell: true).catchError((Object e) {
      ErrorLogger.log(e, null, source: 'cache');
      return ProcessResult(0, 0, '', l10n.explorerFailed(e));
    });
  }

  /// Ask once, then clear.
  Future<void> _confirmClear(int index) async {
    final row = _rows[index];
    final files = row.files();
    if (files.isEmpty) {
      setState(() => _error = l10n.cacheAlreadyEmpty(row.name));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cacheConfirmTitle(row.name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.cacheConfirmTotal(files.length, _size(_sizes[index]))),
            SizedBox(height: 8),
            Text(row.what, style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: 8),
            Text(l10n.cacheConfirmNote,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cacheConfirmOk),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy.add(index);
      _error = null;
    });
    try {
      final removed = await _recycle(files);
      if (!mounted) return;
      if (removed < files.length) {
        _error = '${l10n.cachePartial(row.name, removed, files.length)}${l10n.cacheNoPermission}';
      }
    } catch (e) {
      ErrorLogger.log(e, null, source: 'cache');
      if (!mounted) return;
      _error = l10n.cacheClearFailed(row.name, e);
    } finally {
      if (mounted) {
        setState(() => _busy.remove(index));
        _measure(index);
      }
    }
  }

  /// Send the files to the recycle bin.
  ///
  /// Dart has no recycle API; one PowerShell call clears the whole list
  /// instead of one spawn per file.
  Future<int> _recycle(List<File> files) async {
    final list = File(
        '${AppPaths.tempDir}${Platform.pathSeparator}cache_clear_list.txt');
    list.parent.createSync(recursive: true);
    list.writeAsStringSync(
        [for (final f in files) f.path].join('\n'),
        flush: true);
    final listPath = list.path.replaceAll('"', '""');
    final script = '''
Add-Type -AssemblyName Microsoft.VisualBasic
\$paths = [System.IO.File]::ReadAllLines("$listPath")
\$done = 0
foreach (\$p in \$paths) {
  if ([string]::IsNullOrWhiteSpace(\$p)) { continue }
  try {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
      \$p,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    \$done++
  } catch {}
}
Write-Output \$done
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
    );
    final done = int.tryParse('${result.stdout}'.trim()) ?? 0;
    try {
      if (list.existsSync()) list.deleteSync();
    } catch (_) {}
    return done;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.cacheTitle),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  final busy = _busy.contains(index);
                  final count = _counts[index];
                  final size = _sizes[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.surfaceContainerHighest.withAlpha(70),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(row.name,
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                            Text(
                              count == 0
                                  ? l10n.cacheEmpty
                                  : l10n.cacheCount(count, _size(size)),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(row.what,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white54)),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => _open(row.open),
                              icon: Icon(Icons.folder_open, size: 14),
                              label: Text(l10n.cacheOpen),
                            ),
                            TextButton.icon(
                              onPressed: busy ? null : () => _confirmClear(index),
                              icon: busy
                                  ? SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.delete_outline, size: 14),
                              label: Text(busy ? l10n.cacheClearing : l10n.cacheClear),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 4),
              Text(_error!, style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => setState(_refresh),
          icon: Icon(Icons.refresh, size: 14),
          label: Text(l10n.commonRefresh),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
