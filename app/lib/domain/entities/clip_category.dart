/// How a marked clip reads on the score sheet.
///
/// The descriptions are free-form coaching notes ("顺子进球", "老庄没收皮球"),
/// so the split is keyword-driven. `other` is a real answer, not a failure: an
/// unrecognised note must stay visible instead of being filed under a category
/// it does not belong to.
enum ClipCategory { attack, defence, other }

const _attackKeywords = [
  '进球',
  '破门',
  '得分',
  '助攻',
  '门梁',
  '门柱',
  '横梁',
  '立柱',
];

const _defenceKeywords = [
  '没收',
  '扑出',
  '扑救',
  '神扑',
  '门将',
  '出击',
];

/// Defence wins ties: a note mentioning both a save and a shot is still a save.
ClipCategory classifyClip(String description) {
  final text = description.trim();
  for (final keyword in _defenceKeywords) {
    if (text.contains(keyword)) return ClipCategory.defence;
  }
  for (final keyword in _attackKeywords) {
    if (text.contains(keyword)) return ClipCategory.attack;
  }
  return ClipCategory.other;
}

/// Label used in menus and headings.
String clipCategoryLabel(ClipCategory category) => switch (category) {
      ClipCategory.attack => '进攻',
      ClipCategory.defence => '防守',
      ClipCategory.other => '未分类',
    };
