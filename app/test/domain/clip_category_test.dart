import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/domain/entities/clip_category.dart';

/// The 53 clip descriptions of the 20261021 project, in project order. They
/// drove this feature, so they double as the regression fixture.
const _project20261021 = '''
老庄没收皮球
马指导没收皮球
阿磊助攻阿瑞
阿昂扑出皮球
阿博怒射门梁
阿磊扑出皮球
顺子进球
阿磊扑出皮球
老郑助攻阿军
阿智助攻小成
阿南怒射门梁
老庄打门柱
阿磊扑出皮球
阿博进球
Sos助攻老金
阿南助攻顺子
阿磊助攻阿南
老金助攻Sos
顺子没收皮球
阿智进球
小司助攻阿可
阿昂扑出皮球
阿智进球
顺子没收皮球
顺子助攻阿瑞
顺子进球
阿军扑出皮球
阿博进球
顺子没收皮球
Sos怒射门梁
阿瑞进球
阿军扑出皮球
阿博助攻小司
马指导扑出皮球
老郑扑出皮球
阿磊助攻阿瑞
马指导扑出皮球
阿可扑出皮球
阿昂没收皮球
阿磊没收皮球
马指导助攻老郑
顺子扑出皮球
Black扑出皮球
阿瑞助攻阿磊
老李助攻小成
阿军没收皮球
阿可没收皮球
Sos进球
小司助攻老付
顺子没收皮球
阿昂没收皮球
阿博进球
阿瑞助攻阿磊''';

void main() {
  test('goal, assist and woodwork notes all read as attack', () {
    expect(classifyClip('顺子进球'), ClipCategory.attack);
    expect(classifyClip('阿磊助攻阿瑞'), ClipCategory.attack);
    expect(classifyClip('阿博怒射门梁'), ClipCategory.attack);
    expect(classifyClip('老庄打门柱'), ClipCategory.attack);
  });

  test('keeper notes read as defence', () {
    expect(classifyClip('老庄没收皮球'), ClipCategory.defence);
    expect(classifyClip('阿昂扑出皮球'), ClipCategory.defence);
    expect(classifyClip('门将出击'), ClipCategory.defence);
  });

  test('an unknown note stays visible instead of being filed', () {
    expect(classifyClip(''), ClipCategory.other);
    expect(classifyClip('随便记一下'), ClipCategory.other);
  });

  test('defence wins when a note mentions both', () {
    expect(classifyClip('门将扑出对方进球'), ClipCategory.defence);
  });

  test('the real project splits 29 attack / 24 defence / 0 unknown', () {
    final lines = _project20261021
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    expect(lines, hasLength(53));
    final counts = <ClipCategory, int>{};
    for (final line in lines) {
      final category = classifyClip(line);
      counts[category] = (counts[category] ?? 0) + 1;
    }
    expect(counts[ClipCategory.attack], 29);
    expect(counts[ClipCategory.defence], 24);
    expect(counts[ClipCategory.other], isNull);
  });
}
