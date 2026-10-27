import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:highlight_creator/domain/entities/clip_category.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

/// Show every marked clip of the open project split into attack and defence,
/// one `index description` line each, with the text ready to copy.
Future<void> openClipBreakdownDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => const ClipBreakdownDialog(),
  );
}

/// One classified line: the clip's 1-based position in the project (the same
/// number Make stamps on the transition card) and its note.
class _Line {
  final int index;
  final String description;

  const _Line(this.index, this.description);

  String get text => '$index $description';
}

class ClipBreakdownDialog extends ConsumerWidget {
  const ClipBreakdownDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final record = ref.watch(recordProvider);
    final slots = record.timeslots;

    final grouped = <ClipCategory, List<_Line>>{
      for (final category in ClipCategory.values) category: <_Line>[],
    };
    for (var i = 0; i < slots.length; i++) {
      final Timeslot slot = slots[i];
      final description =
          slot.description.trim().isEmpty ? '（无描述）' : slot.description.trim();
      grouped[classifyClip(slot.description)]!.add(_Line(i + 1, description));
    }

    final attacks = grouped[ClipCategory.attack]!;
    final defences = grouped[ClipCategory.defence]!;
    final others = grouped[ClipCategory.other]!;
    final projectName = record.selectedProject?.name ?? '未命名项目';

    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width < 860 ? size.width - 48 : 820,
        height: size.height < 760 ? size.height - 48 : 700,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 10),
              child: Row(
                children: [
                  const Icon(Icons.list_alt_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text('时间片段分类明细', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                '$projectName · 共 ${slots.length} 条 ·'
                ' 进攻 ${attacks.length} · 防守 ${defences.length}'
                '${others.isEmpty ? '' : ' · 未分类 ${others.length}'}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: slots.isEmpty
                  ? Center(
                      child: Text('当前项目还没有片段',
                          style: theme.textTheme.bodyMedium),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section(context, ref, attacks, 'attack_breakdown'),
                          const SizedBox(height: 14),
                          _section(context, ref, defences, 'defence_breakdown'),
                          if (others.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _section(
                                context, ref, others, 'other_breakdown'),
                          ],
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(
                children: [
                  Text('序号与 Make 时转场卡上的编号一致',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: slots.isEmpty
                        ? null
                        : () => _copy(
                              context,
                              '${_sectionText(attacks)}\n\n${_sectionText(defences)}',
                              '全部内容',
                            ),
                    icon: const Icon(Icons.copy_all, size: 16),
                    label: const Text('复制全部'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Heading plus one line per clip, for the copy button and the view.
  static String _sectionText(List<_Line> lines) {
    if (lines.isEmpty) return '（无）';
    return [for (final line in lines) line.text].join('\n');
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref,
    List<_Line> lines,
    String keyName,
  ) {
    final theme = Theme.of(context);
    // Defence lines are listed under the label that owns them; the label and
    // the count come from the same list so they can never disagree.
    final category = keyName.startsWith('attack')
        ? ClipCategory.attack
        : keyName.startsWith('defence')
            ? ClipCategory.defence
            : ClipCategory.other;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('${clipCategoryLabel(category)} ${lines.length} 条',
                style: theme.textTheme.labelLarge),
            const Spacer(),
            if (lines.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    _copy(context, _sectionText(lines), clipCategoryLabel(category)),
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('复制'),
              ),
          ],
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withAlpha(10)),
          ),
          child: SelectableText(
            _sectionText(lines),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$label'), duration: const Duration(seconds: 2)),
    );
  }
}
