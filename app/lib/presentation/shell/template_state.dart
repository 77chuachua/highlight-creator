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

  /// Select a startup template and, when it belongs to a built-in design set,
  /// that set's transition and ending with it -a set behaves like one choice.
  ///
  /// Only an explicit startup pick does this. Picking a transition or ending by
  /// hand is final: nothing re-applies the set afterwards.
  Future<void> selectStartupWithSet(String? templateId) async {
    select(TemplateType.startup, templateId);
    if (templateId == null) return;
    final repo = ref.read(templateRepositoryProvider);
    final template = await repo.getById(templateId);
    final set = TemplateGeneratorService.setOfPath(template?.path ?? '');
    if (set == null) return;

    final wanted = <TemplateType, String>{
      TemplateType.transition: set.transition.fileName,
      TemplateType.ending: set.ending.fileName,
    };
    for (final entry in wanted.entries) {
      final list = await repo.listByType(entry.key);
      for (final candidate in list) {
        final name = candidate.path.split(RegExp(r'[\\/]')).last;
        if (name == entry.value) {
          select(entry.key, candidate.id);
          break;
        }
      }
    }
  }

  void clear() {
    state = {};
  }
}

final selectedTemplatesProvider = NotifierProvider<SelectedTemplatesNotifier,
    Map<TemplateType, String?>>(SelectedTemplatesNotifier.new);

final templateRefreshProvider = StateProvider<int>((ref) => 0);
