import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/services/template_generator_service.dart';

class SelectedTemplatesNotifier
    extends Notifier<Map<TemplateType, String?>> {
  @override
  Map<TemplateType, String?> build() => {};

  void select(TemplateType type, String? templateId) {
    state = {...state, type: templateId};
  }

  /// Select a startup template and its design set's transition and ending with
  /// it — a set behaves like one choice.
  ///
  /// The built-in sets are matched by their spec file names. Anything else the
  /// registry holds (the legacy blue/yellow packs, downloaded online sets,
  /// imported packs) is matched by [TemplateGeneratorService.setKeyOfPath], so
  /// "pick a startup pack" also works for templates this build did not ship.
  ///
  /// Only an explicit startup pick does this. Picking a transition or ending by
  /// hand is final: nothing re-applies the set afterwards.
  Future<void> selectStartupWithSet(String? templateId) async {
    select(TemplateType.startup, templateId);
    if (templateId == null) return;
    final repo = ref.read(templateRepositoryProvider);
    final template = await repo.getById(templateId);
    final path = template?.path ?? '';

    final set = TemplateGeneratorService.setOfPath(path);
    final key = set?.id ?? TemplateGeneratorService.setKeyOfPath(path);
    if (key == null) return;

    // A built-in set names its three files outright; a derived key has to be
    // compared against every candidate of the two other types.
    final wanted = <TemplateType, String?>{
      TemplateType.transition: set?.transition.fileName,
      TemplateType.ending: set?.ending.fileName,
    };
    for (final type in [TemplateType.transition, TemplateType.ending]) {
      final fileName = wanted[type];
      final currentId = state[type];
      if (currentId != null) {
        // Keep a row that already belongs to this pack: a pack can hold more
        // than one ending (an online set re-published under a new revision
        // leaves the old render registered), and the user's exact pick must not
        // be swapped for whichever row happens to come first.
        final current = await repo.getById(currentId);
        final currentKey = current == null
            ? null
            : TemplateGeneratorService.setOfPath(current.path)?.id ??
                TemplateGeneratorService.setKeyOfPath(current.path);
        if (currentKey == key) continue;
      }
      final list = await repo.listByType(type);
      Template? match;
      for (final candidate in list) {
        final name = candidate.path.split(RegExp(r'[\\/]')).last;
        final same = fileName != null
            ? name == fileName
            : TemplateGeneratorService.setKeyOfPath(candidate.path) == key;
        if (same) {
          match = candidate;
          break;
        }
      }
      if (match != null) select(type, match.id);
    }
  }

  void clear() {
    state = {};
  }
}

final selectedTemplatesProvider = NotifierProvider<SelectedTemplatesNotifier,
    Map<TemplateType, String?>>(SelectedTemplatesNotifier.new);

final templateRefreshProvider = StateProvider<int>((ref) => 0);
