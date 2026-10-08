import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/domain/entities/template.dart';

class SelectedTemplatesNotifier
    extends Notifier<Map<TemplateType, String?>> {
  @override
  Map<TemplateType, String?> build() => {};

  void select(TemplateType type, String? templateId) {
    state = {...state, type: templateId};
  }

  void clear() {
    state = {};
  }
}

final selectedTemplatesProvider = NotifierProvider<SelectedTemplatesNotifier,
    Map<TemplateType, String?>>(SelectedTemplatesNotifier.new);

final templateRefreshProvider = StateProvider<int>((ref) => 0);
