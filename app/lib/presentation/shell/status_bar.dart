import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

/// Status bar showing project summary — per Windows UI design.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(recordProvider);
    final project = state.selectedProject;
    final videoPath = ref.watch(videoPlayerProvider.select((s) => s.videoPath));
    final sources = project?.sources ?? const <VideoSource>[];

    String? videoInfo;
    if (videoPath != null && videoPath.isNotEmpty) {
      final base = videoPath.split(RegExp(r'[\\/]')).last;
      for (final s in sources) {
        if (s.filePath == videoPath ||
            s.filePath.split(RegExp(r'[\\/]')).last == base) {
          if (s.width > 0 && s.codecName.isNotEmpty) {
            videoInfo = '${s.width}\u00d7${s.height} \u00b7 ${s.codecName} \u00b7 ${s.fps}fps';
          }
          break;
        }
      }
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            project != null ? '${l10n.projectPrefix}${project.name}' : l10n.noProject,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          if (project != null) ...[
            const Text(' │ ', style: TextStyle(fontSize: 11, color: Colors.white24)),
            Text(
              '${project.sources.length}${l10n.sourceFilesSuffix}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const Text(' │ ', style: TextStyle(fontSize: 11, color: Colors.white24)),
            Text(
              '${state.timeslots.length}${l10n.timeslotsSuffix}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
          const Spacer(),
          if (videoInfo != null)
            Text(
              videoInfo,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          const SizedBox(width: 8),
          Text(
            l10n.appVersion,
            style: const TextStyle(fontSize: 11, color: Colors.white24),
          ),
        ],
      ),
    );
  }
}
