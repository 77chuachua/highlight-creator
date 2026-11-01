import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/ai_marking_service.dart';

/// The `prompt_tok` field on an `[ai-marking] cand ...` line is a diagnostic
/// only; these checks keep the estimate and the reply parser honest without
/// touching the decision path.
void main() {
  test('input-token estimate sums per-image patches, each clamped to 1024', () {
    // 896×1008 is what `scale=448:-2,tile=2x4` produces for 16:9 footage:
    // 32×36 patches of 28 px. Each half-frame zoom is 3584×504 (128×18), still
    // over the documented per-image ceiling. Three views are three clamps plus
    // the text and envelope counted once.
    final wide = _jpeg(896, 1008);
    final zoom = _jpeg(3584, 504);
    expect(
      DeepSeekVisionClient.estimateInputTokens([wide], instruction: ''),
      32 + DeepSeekVisionClient.maxImageTokens,
    );
    expect(
      DeepSeekVisionClient.estimateInputTokens([wide, zoom, zoom],
          instruction: ''),
      32 + 3 * DeepSeekVisionClient.maxImageTokens,
    );
  });

  test('input-token estimate falls back to the byte size', () {
    expect(
      DeepSeekVisionClient.estimateInputTokens(
        [
          Uint8List.fromList([1, 2, 3])
        ],
        instruction: '',
      ),
      1 + 32,
    );
    expect(DeepSeekVisionClient.estimateInputTokens(const <Uint8List>[]), 0);
  });

  test('three images share one user message, in prompt order', () {
    final body = DeepSeekVisionClient.requestBody(
      model: 'deepseek-flash',
      base64Jpegs: const ['wide', 'top', 'bottom'],
    );
    final messages = body['messages'] as List;
    expect(messages, hasLength(1));
    final content = (messages.single as Map)['content'] as List;
    expect(content, hasLength(4)); // text + 3 image_url
    expect((content.first as Map)['type'], 'text');
    expect(
      [
        for (final part in content.skip(1))
          ((part as Map)['image_url'] as Map)['url'],
      ],
      [
        'data:image/jpeg;base64,wide',
        'data:image/jpeg;base64,top',
        'data:image/jpeg;base64,bottom',
      ],
    );
  });

  test('one candidate is judged from three 8-frame views: wide, top, bottom',
      () {
    final filters = AiMarkingService.tileFilters;
    expect(filters, hasLength(3));
    // fps=1 × 8 tile slots = the whole 8 s window in every view.
    expect(filters[0], 'fps=1,scale=448:-2,tile=2x4');
    expect(filters[1], startsWith('fps=1,'));
    expect(filters[1], contains('crop=iw:ih/2:0:0'));
    expect(filters[1], endsWith('tile=4x2'));
    expect(filters[2], startsWith('fps=1,'));
    expect(filters[2], contains('crop=iw:ih/2:0:ih/2'));
    expect(filters[2], endsWith('tile=4x2'));
  });

  test('a fenced JSON object surrounded by prose still parses', () {
    final judgement = DeepSeekVisionClient.parseContent(
        '好的,结果如下:\n```json\n{"highlight": true, "kind": "goal", '
        '"description": "禁区外远射破门"}\n```\n希望有帮助。');
    expect(judgement.highlight, isTrue);
    expect(judgement.kind, 'goal');
    expect(judgement.description, '禁区外远射破门');
  });

  test('the first balanced object wins, braces inside strings do not count',
      () {
    expect(
      DeepSeekVisionClient.firstJsonObject(
          'x {"description": "a } brace", "kind": "goal"} tail {'),
      '{"description": "a } brace", "kind": "goal"}',
    );
  });

  test('content as an array of parts is joined into text', () {
    expect(
      DeepSeekVisionClient.contentText([
        {'type': 'text', 'text': '{"highlight": false,'},
        {'type': 'text', 'text': ' "kind": "none"}'},
      ]),
      '{"highlight": false, "kind": "none"}',
    );
  });

  test('a truncated object is a failed candidate, not a verdict', () {
    expect(
      DeepSeekVisionClient.firstJsonObject('{"highlight": true, "descr'),
      isNull,
    );
    expect(
      () => DeepSeekVisionClient.parseContent('{"highlight": tru'),
      throwsA(isA<AiMarkingException>()),
    );
  });
}

/// SOI + a bare SOF0 carrying [width]×[height]; enough for a header scan.
Uint8List _jpeg(int width, int height) {
  final bytes = Uint8List(20);
  bytes[0] = 0xFF; // SOI
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  bytes[3] = 0xC0; // SOF0
  bytes[4] = 0x00;
  bytes[5] = 0x0B; // segment length
  bytes[6] = 0x08; // sample precision
  bytes[7] = height >> 8;
  bytes[8] = height & 0xFF;
  bytes[9] = width >> 8;
  bytes[10] = width & 0xFF;
  return bytes;
}
