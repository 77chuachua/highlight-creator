import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/font_name.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/template_manifest.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/services/template_generator_service.dart';
import 'package:highlight_creator/services/template_plugin_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const _fontPresets = <String, String>{
  'Microsoft YaHei (微软雅黑)': r'C:\Windows\Fonts\msyh.ttc',
  'Microsoft YaHei Bold': r'C:\Windows\Fonts\msyhbd.ttc',
  'SimHei (黑体)': r'C:\Windows\Fonts\simhei.ttf',
  'SimSun (宋体)': r'C:\Windows\Fonts\simsun.ttc',
  'KaiTi (楷体)': r'C:\Windows\Fonts\simkai.ttf',
  'Segoe UI': r'C:\Windows\Fonts\segoeui.ttf',
  'Arial': r'C:\Windows\Fonts\arial.ttf',
  'Impact': r'C:\Windows\Fonts\impact.ttf',
  'Consolas': r'C:\Windows\Fonts\consola.ttf',
};

const _swatches = <int>[
  0xFFF5C42D,
  0xFFFFFFFF,
  0xFF69F0AE,
  0xFF42A5F5,
  0xFFEF5350,
  0xFFAB47BC,
  0xFFFFA726,
  0xFF26C6DA,
];

const _defaultFontSize = 48.0;
const _defaultFontColor = 0xFFF5C42D;
const _defaultFontKey = 'Microsoft YaHei (微软雅黑)';
const _defaultTextPos = _TextPos.middle;

enum _TextPos { top, middle, bottom }

class _Entry {
  final String key;
  final String label;
  final TemplateSpec? spec;
  final Template? userTemplate;

  /// Set for a template downloaded from the plugin catalogue rather than built
  /// in. Null for everything that ships with the app.
  final RemoteTemplateSpec? remote;

  _Entry.builtin(TemplateSpec s)
      : spec = s,
        key = s.fileName,
        label = s.label,
        userTemplate = null,
        remote = null;

  _Entry.user(Template t)
      : userTemplate = t,
        key = t.path,
        label = t.name,
        spec = null,
        remote = null;

  _Entry.plugin(RemoteTemplateSpec r)
      : remote = r,
        key = 'plugin:${r.cacheKey}',
        label = r.name,
        userTemplate = null,
        spec = null;

  TemplateType get type {
    if (userTemplate != null) return userTemplate!.type;
    if (remote != null) return remote!.type;
    return switch (spec!.category) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
  }

  /// Where this entry's rendered video lives once it exists.
  String? get resolvedPath {
    if (userTemplate != null) return userTemplate!.path;
    if (remote != null) {
      return '${TemplatePluginService.pluginDir}${Platform.pathSeparator}'
          '${remote!.cacheKey}.mp4';
    }
    return '${TemplateGeneratorService.templatesDir}'
        '${Platform.pathSeparator}${spec!.fileName}';
  }
}

class TemplateEditorDialog extends ConsumerStatefulWidget {
  final TemplateCategory initialCategory;

  /// Default title for embedded startup templates: the localized placeholder.
  static String defaultStartupTitle(String lang) =>
      lang == '中文' ? '精彩集锦' : 'Awesome Highlight';

  /// The text the shared preview-text field must show for [template]:
  /// its saved title, or [fallback] when it has none. Never the previous
  /// category's text — the field is shared across all three tabs.
  static String resolvePreviewText(Template? template, String fallback) {
    final title = template?.title;
    return (title == null || title.isEmpty) ? fallback : title;
  }

  const TemplateEditorDialog({
    super.key,
    this.initialCategory = TemplateCategory.startup,
  });

  @override
  ConsumerState<TemplateEditorDialog> createState() =>
      _TemplateEditorDialogState();
}

class _TemplateEditorDialogState
    extends ConsumerState<TemplateEditorDialog> {
  late TemplateCategory _category;
  late _Entry _selected;

  late final TextEditingController _textCtrl;
  String? _fontKey = _defaultFontKey;
  String? _customFont;

  bool _showText = true;
  String _s(String zh, String en) => ref.read(languageProvider) == '中文' ? zh : en;

  double _fontSize = _defaultFontSize;
  Color _color = const Color(_defaultFontColor);
  _TextPos _pos = _defaultTextPos;
  bool _muted = true;

  VideoProcessingService? _vps;
  TemplateGeneratorService? _genSvc;
  TemplatePluginService? _pluginSvc;

  /// Templates published in the remote catalogue and matching the current tab.
  List<RemoteTemplateSpec> _remoteSpecs = const [];

  /// Non-fatal note about the catalogue, e.g. it could not be refreshed and a
  /// cached copy is being shown. Deliberately not `_error`: a missing catalogue
  /// must never make the built-in templates look broken.
  String? _catalogNote;

  Player? _player;
  VideoController? _controller;

  Timer? _debounce;
  Timer? _saveDebounce;
  Timer? _titleSaveDebounce;
  int _gen = 0;
  bool _busy = false;
  String? _status;
  String? _error;
  double _progress = 0;

  late Directory _tempDir;
  final Map<String, String> _thumbCache = {};
  List<Template> _userTemplates = [];

  @override
  void initState() {
    super.initState();
    final lang = ref.read(languageProvider);
    _textCtrl = TextEditingController(
        text: TemplateEditorDialog.defaultStartupTitle(lang));
    _category = widget.initialCategory;
    _selected = _Entry.builtin(TemplateGeneratorService.allSpecs
        .firstWhere((s) => s.category == _category));
    _tempDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'hl_preview_${DateTime.now().millisecondsSinceEpoch}',
    );
    _tempDir.createSync(recursive: true);

    _loadUserTemplates();
    _applyFontConfig(_selected);
    _loadTemplateTitle(_selected);
    _seedFromSelection(_category);

    VideoProcessingService.findFfmpeg().then((p) {
      if (!mounted) return;
      _vps = VideoProcessingService(ffmpegPath: p);
      _genSvc = TemplateGeneratorService(_vps!);
      _pluginSvc = TemplatePluginService(_vps!);
      setState(() {});
      _scheduleRegen(immediate: true);
      _loadCatalogue();
    });
  }

  /// Fetch the plugin catalogue in the background.
  ///
  /// Failure is reported as a note, not an error: the built-in sets must stay
  /// fully usable on a machine that can never reach the catalogue.
  Future<void> _loadCatalogue() async {
    final svc = _pluginSvc;
    if (svc == null) return;
    String? note;
    try {
      final manifest = await svc.loadManifest();
      if (!mounted) return;
      setState(() {
        _remoteSpecs = manifest.templates;
        _catalogNote = null;
      });
    } on TemplatePluginManifestError catch (e) {
      note = e.servedFromCache
          ? _s('模板清单离线，显示已缓存版本',
              'Template catalogue offline, showing cached copy')
          : _s('无法加载模板清单', 'Could not load template catalogue');
      if (mounted) setState(() => _catalogNote = note);
    } catch (_) {
      // Never let an unexpected transport shape break the dialog.
    }
  }

  /// Catalogue templates of the active tab, as card entries.
  List<_Entry> _remoteEntries() {
    final type = switch (_category) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
    return _remoteSpecs
        .where((r) => r.type == type)
        .map(_Entry.plugin)
        .toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _saveDebounce?.cancel();
    _titleSaveDebounce?.cancel();
    _player?.dispose();
    _textCtrl.dispose();
    try {
      _tempDir.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadUserTemplates() async {
    final repo = ref.read(templateRepositoryProvider);
    final type = switch (_category) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
    final list = await repo.listByType(type);
    if (!mounted) return;
    setState(() => _userTemplates = list);
  }

  /// Map a stored template back to a dialog entry (builtin card if its path
  /// matches an embedded spec, otherwise the user-template entry).
  static _Entry _entryFor(Template t) {
    final cat = switch (t.type) {
      TemplateType.startup => TemplateCategory.startup,
      TemplateType.transition => TemplateCategory.transition,
      TemplateType.ending => TemplateCategory.ending,
      TemplateType.backgroundMusic => TemplateCategory.transition,
    };
    for (final s in TemplateGeneratorService.allSpecs
        .where((x) => x.category == cat)) {
      if (t.path.endsWith(s.fileName)) return _Entry.builtin(s);
    }
    return _Entry.user(t);
  }

  /// Seed the editor with the currently-selected template for [category] so
  /// the preview dialog, the sidebar and the config dialog always share the
  /// same selection.
  Future<void> _seedFromSelection(TemplateCategory category) async {
    final type = switch (category) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
    final selectedId = ref.read(selectedTemplatesProvider)[type];
    if (selectedId == null) return;
    final t = await ref.read(templateRepositoryProvider).getById(selectedId);
    if (t == null || !mounted) return;
    final entry = _entryFor(t);
    // Always re-apply config + title — even when the card is already
    // selected, the shared text field must be refreshed for this category
    // (e.g. switching from ending to startup must reload the startup title).
    setState(() => _selected = entry);
    await _applyFontConfig(entry);
    await _loadTemplateTitle(entry);
    if (mounted) _scheduleRegen(immediate: true);
  }

  /// Persist the current dialog selection back into the shared
  /// [selectedTemplatesProvider] so every UI surfaces the same template.
  Future<void> _selectEntry(_Entry entry) async {
    final repo = ref.read(templateRepositoryProvider);
    final type = entry.type;
    Template? t = entry.userTemplate;
    if (t == null && entry.spec != null) {
      final dir = TemplateGeneratorService.templatesDir;
      final templatePath = '$dir${Platform.pathSeparator}${entry.spec!.fileName}';
      final existing = await repo.listByType(type);
      t = existing.where((x) => x.path == templatePath).firstOrNull;
      t ??= await repo.save(Template(
        id: '',
        name: entry.spec!.label,
        path: templatePath,
        type: type,
      ));
    }
    if (t != null) {
      ref.read(selectedTemplatesProvider.notifier).select(type, t.id);
    }
  }

  String? get _escapedFont {
    final raw = _customFont ?? (_fontKey != null ? _fontPresets[_fontKey] : null);
    if (raw == null) return null;
    return raw.replaceAll('\\', '/').replaceAll(':', r'\:');
  }

  String get _colorHex {
    final v = _color.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }

  /// Overlay `y` for the active category: a transition reserves its text zone at
  /// the frame center, a startup/ending plate sits higher (see
  /// [VideoProcessingService.textYExpr]).
  String get _yExpr => VideoProcessingService.textYExpr(
        switch (_pos) {
          _TextPos.top => 'top',
          _TextPos.middle => 'middle',
          _TextPos.bottom => 'bottom',
        },
        transition: _category == TemplateCategory.transition,
      );

  String _catLabel(TemplateCategory c) => switch (c) {
        TemplateCategory.startup => _s('开场', 'Startup'),
        TemplateCategory.transition => _s('转场', 'Transition'),
        TemplateCategory.ending => _s('结尾', 'Ending'),
      };

  Future<void> _applyFontConfig(_Entry entry) async {
    Template? t = entry.userTemplate;
    if (t == null && entry.spec != null) {
      final spec = entry.spec!;
      final dir = TemplateGeneratorService.templatesDir;
      final templatePath = '$dir${Platform.pathSeparator}${spec.fileName}';
      final type = switch (spec.category) {
        TemplateCategory.startup => TemplateType.startup,
        TemplateCategory.transition => TemplateType.transition,
        TemplateCategory.ending => TemplateType.ending,
      };
      final repo = ref.read(templateRepositoryProvider);
      final list = await repo.listByType(type);
      t = list.where((x) => x.path == templatePath).firstOrNull;
    }
    if (!mounted) return;
    setState(() {
      if (t?.fontSize != null) {
        _fontSize = t!.fontSize!.toDouble();
      } else {
        _fontSize = _defaultFontSize;
      }
      if (t?.fontColor != null) {
        final hex = t!.fontColor!.replaceFirst('#', '');
        final v = int.tryParse(hex, radix: 16);
        _color = v != null ? Color(0xFF000000 | v) : const Color(_defaultFontColor);
      } else {
        _color = const Color(_defaultFontColor);
      }
      if (t?.fontPath != null && t!.fontPath!.isNotEmpty) {
        final raw = t.fontPath!;
        // Map back to a preset (friendly) name when the stored path matches one.
        final presetKey = _presetKeyForPath(raw);
        if (presetKey != null) {
          _customFont = null;
          _fontKey = presetKey;
        } else {
          _customFont = raw;
          _fontKey = null;
        }
      } else {
        _customFont = null;
        _fontKey = _defaultFontKey;
      }
      if (t?.textPosition != null) {
        _pos = switch (t!.textPosition) {
          'top' => _TextPos.top,
          'bottom' => _TextPos.bottom,
          _ => _TextPos.middle,
        };
      } else {
        _pos = _defaultTextPos;
      }
      _showText = t?.showText ?? true;
    });
  }

  /// Font name shown in the dropdown / hint: the preset label for preset
  /// paths, otherwise the real family name parsed from the font file.
  String _displayFontName() {
    if (_customFont != null) {
      final name = readFontFamily(_customFont!);
      if (name != null && name.isNotEmpty) return name;
      return _customFont!.split(RegExp(r'[/\\]')).last;
    }
    if (_fontKey != null) return _fontKey!;
    return _s('选择字体', 'Select Font');
  }

  static String? _presetKeyForPath(String raw) {
    final norm = raw.toLowerCase().replaceAll('\\', '/');
    for (final e in _fontPresets.entries) {
      if (e.value.toLowerCase().replaceAll('\\', '/') == norm) return e.key;
    }
    return null;
  }

  void _saveFontConfig() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
      final repo = ref.read(templateRepositoryProvider);
      Template? t = _selected.userTemplate;

      // For built-in templates, find or create the registered version.
      if (t == null && _selected.spec != null) {
        final spec = _selected.spec!;
        final dir = TemplateGeneratorService.templatesDir;
        final templatePath = '$dir${Platform.pathSeparator}${spec.fileName}';
        final type = switch (spec.category) {
          TemplateCategory.startup => TemplateType.startup,
          TemplateCategory.transition => TemplateType.transition,
          TemplateCategory.ending => TemplateType.ending,
        };
        final list = await repo.listByType(type);
        t = list.where((x) => x.path == templatePath).firstOrNull;
        t ??= await repo.save(Template(
          id: '',
          name: spec.label,
          path: templatePath,
          type: type,
        ));
      }

      if (t == null) return;
      await repo.save(t.copyWith(
        fontSize: _fontSize.round(),
        fontColor: _colorHex,
        fontPath: _customFont ?? (_fontKey != null ? _fontPresets[_fontKey] : null),
        textPosition: switch (_pos) {
          _TextPos.top => 'top',
          _TextPos.middle => 'middle',
          _TextPos.bottom => 'bottom',
        },
        showText: _showText,
      ));
      if (mounted) ref.read(templateRefreshProvider.notifier).state++;
    });
  }

  /// Download a catalogue template's script and render it.
  ///
  /// The two phases are reported separately because they fail for completely
  /// different reasons and the user's next action differs: a download failure
  /// is the network or a tampered file, a render failure is the script itself.
  /// Returns null after setting `_error`, or the rendered path on success.
  Future<String?> _generatePlugin(int token) async {
    final svc = _pluginSvc;
    final remote = _selected.remote;
    if (svc == null || remote == null) return null;

    void fail(Object e) {
      if (token != _gen || !mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
        _status = null;
      });
    }

    // Phase 1: script download. Weighted to the first 40% of the bar so the
    // two phases read as separate steps rather than one opaque wait. The path
    // is not needed here — [TemplatePluginService.render] re-reads the cached
    // script — but fetching it now is what surfaces a download or policy
    // failure *before* the render starts, which is the whole point.
    setState(() =>
        _status = _s('下载模板脚本…', 'Downloading template script…'));
    try {
      await svc.ensureScript(
        remote,
        onProgress: (p) {
          if (token != _gen || !mounted) return;
          setState(() => _progress = p * 0.4);
        },
      );
    } on TemplatePluginDownloadError catch (e) {
      fail(e);
      return null;
    } on TemplatePluginRejectedError catch (e) {
      fail(e);
      return null;
    } catch (e) {
      fail(TemplatePluginDownloadError('$e', remote.script.url));
      return null;
    }
    if (token != _gen || !mounted) return null;

    // Phase 2: render.
    setState(() => _status = _s('生成模板…', 'Rendering template…'));
    try {
      final path = await svc.render(
        remote,
        onProgress: (p) {
          if (token != _gen || !mounted) return;
          setState(() => _progress = 0.4 + p * 0.6);
        },
        onScriptProgress: (_) {
          // Already downloaded in phase 1; nothing to report.
        },
      );
      if (token != _gen || !mounted) return null;
      _thumbCache.remove(_selected.key);
      return path;
    } on TemplatePluginRenderError catch (e) {
      fail(e);
      return null;
    } on TemplatePluginDownloadError catch (e) {
      // The script cache was invalidated between the phases.
      fail(e);
      return null;
    } on TemplatePluginRejectedError catch (e) {
      fail(e);
      return null;
    } catch (e) {
      fail(TemplatePluginRenderError('$e', ''));
      return null;
    }
  }

  void _scheduleRegen({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _doGenerate();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _doGenerate);
  }

  Future<void> _doGenerate() async {
    final vps = _vps;
    if (vps == null || !mounted) return;

    final token = ++_gen;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = _s('准备模板底片…', 'Preparing template base\u2026');
    });

    try {
      String base;
      if (_selected.remote != null) {
        final rendered = await _generatePlugin(token);
        if (rendered == null || token != _gen || !mounted) return;
        base = rendered;
        _autoRegister(base);
      } else if (_selected.spec != null) {
        final svc = _genSvc;
        if (svc == null) return;
        base = await svc.ensureFile(
          _selected.spec!,
          onProgress: (p) {
            if (token != _gen || !mounted) return;
            setState(() => _progress = p);
          },
        );
        if (token != _gen || !mounted) return;
        _autoRegister(base);
      } else {
        base = _selected.userTemplate!.path;
        if (!File(base).existsSync()) {
          setState(() {
            _error = '文件不存在: $base';
            _busy = false;
            _status = null;
          });
          return;
        }
      }

      if (!_showText) {
        // Use base video directly without text overlay.
        await _openPreview(token, base);
        if (token != _gen || !mounted) return;
        setState(() { _busy = false; _status = null; });
        return;
      }

      setState(() => _status = _s('渲染文字预览…', 'Rendering text preview\u2026'));

      final out =
          '${_tempDir.path}${Platform.pathSeparator}preview_$token.mp4';
      final res = await vps.overlayText(
        inputPath: base,
        outputPath: out,
        text: _textCtrl.text,
        fontPath: _escapedFont,
        fontSize: _fontSize.round(),
        fontColor: _colorHex,
        yExpr: _yExpr,
      );
      if (token != _gen || !mounted) return;

      if (res.exitCode != 0) {
        setState(() {
          _error = '${res.stderr}'.trim();
          _busy = false;
          _status = null;
        });
        return;
      }

      await _openPreview(token, out);
      if (token != _gen || !mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
    } catch (e) {
      if (token != _gen || !mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
        _status = null;
      });
    }
  }

  /// Replace the preview [Player]/[VideoController] and play [path].
  ///
  /// media_kit does not reliably re-render when the same [Player] is reopened
  /// with a second media, so switching templates left the preview stuck on the
  /// previous frame/black (issues.md). A fresh player per preview mirrors the
  /// preview dialog and the main player view model, which both recreate the
  /// player per source.
  Future<void> _openPreview(int token, String path) async {
    final old = _player;
    final player = Player();
    final controller = VideoController(player);
    await player.setPlaylistMode(PlaylistMode.single);
    await player.setVolume(_muted ? 0 : 100);
    if (token != _gen || !mounted) {
      await player.dispose();
      return;
    }
    setState(() {
      _player = player;
      _controller = controller;
    });
    await player.open(Media(path));
    await old?.dispose();
  }

  void _autoRegister(String path) {
    final entry = _selected;
    final TemplateType type = entry.type;
    final name = entry.remote?.name ?? entry.spec?.label;
    if (name == null) return;
    final repo = ref.read(templateRepositoryProvider);
    repo.listByType(type).then((existing) {
      if (existing.any((t) => t.path == path)) return;
      repo.save(Template(
        id: '',
        name: name,
        path: path,
        type: type,
      ));
      if (mounted) {
        _loadUserTemplates();
        ref.read(templateRefreshProvider.notifier).state++;
      }
    });
  }

  Future<String?> _thumb(_Entry entry) async {
    final key = entry.key;
    if (_thumbCache.containsKey(key)) return _thumbCache[key];
    final vps = _vps;
    if (vps == null) return null;

    final src = entry.resolvedPath;
    if (src == null || !File(src).existsSync()) return null;

    final out = '${_tempDir.path}${Platform.pathSeparator}th_${key.hashCode}.png';
    final res = await vps.extractFrame(
      sourcePath: src,
      timestampSecs: 0.4,
      outputPath: out,
      width: 168,
      height: 94,
    );
    if (res.exitCode == 0 && File(out).existsSync()) {
      _thumbCache[key] = out;
      return out;
    }
    return null;
  }

  Future<void> _browseFont() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf', 'ttc'],
    );
    final path = r?.files.single.path;
    if (path != null) {
      setState(() {
        _customFont = path;
        _fontKey = null;
      });
      _saveFontConfig();
      _scheduleRegen();
    }
  }

  void _restoreDefaults() {
    setState(() {
      _textCtrl.text = TemplateEditorDialog.defaultStartupTitle(
          ref.read(languageProvider));
      _fontKey = _defaultFontKey;
      _customFont = null;
      _fontSize = _defaultFontSize;
      _color = const Color(_defaultFontColor);
      _pos = _defaultTextPos;
      _showText = true;
    });
    _saveFontConfig();
    _scheduleRegen();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        width: 1100,
        height: 680,
        child: Column(
          children: [
            _buildTitleBar(theme),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: _buildLeftRail(theme)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildPreview(theme)),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildActions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 20),
          const SizedBox(width: 8),
          Text(_s('模板编辑和预览', 'Template Editor & Preview'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(_s('模板', 'Template')),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TemplateCategory>(
              segments: [
                for (final c in TemplateCategory.values)
                  ButtonSegment(value: c, label: Text(_catLabel(c))),
              ],
              selected: {_category},
              onSelectionChanged: (s) {
                setState(() {
                  _category = s.first;
                  _selected = _Entry.builtin(TemplateGeneratorService.allSpecs
                      .firstWhere((x) => x.category == _category));
                });
                _loadUserTemplates();
                // Refresh the shared text field for the new category too, so
                // the regen below never burns the previous category's text
                // into the preview (and so tabs without a selection still
                // reset the field).
                _applyFontConfig(_selected).then((_) async {
                  await _loadTemplateTitle(_selected);
                  _scheduleRegen(immediate: true);
                });
                _seedFromSelection(_category);
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildTemplateCards(theme),
          _buildRemoteInfo(theme) ?? const SizedBox.shrink(),
          const SizedBox(height: 20),
          _section(_s('字体', 'Font')),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(
            controller: _textCtrl,
            decoration: InputDecoration(
              labelText: _s('预览文字', 'Preview Text'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) { _scheduleRegen(); _saveTextAsTitle(); },
          )),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(_showText ? Icons.visibility : Icons.visibility_off, size: 20),
            tooltip: _showText
                ? _s('隐藏文字', 'Hide text')
                : _s('显示文字', 'Show text'),
            onPressed: () {
              setState(() => _showText = !_showText);
              _saveFontConfig();
              _scheduleRegen(immediate: true);
            },
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
          ),
          ],
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: _customFont == null ? _fontKey : null,
            isExpanded: true,
            hint: Text(
              _displayFontName(),
              overflow: TextOverflow.ellipsis,
            ),
            items: [
              for (final k in _fontPresets.keys)
                DropdownMenuItem(
                  value: k,
                  child: Text(k, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _fontKey = v;
                _customFont = null;
              });
              _saveFontConfig();
              _scheduleRegen();
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _browseFont,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(_s('浏览字体文件…', 'Browse Font File\u2026')),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(_s('字号', 'Font Size'), style: const TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 16,
                  max: 96,
                  divisions: 40,
                  onChanged: (v) {
                    setState(() => _fontSize = v);
                    _saveFontConfig();
                    _scheduleRegen();
                  },
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('${_fontSize.round()} px',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_s('颜色', 'Color'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _swatches)
                GestureDetector(
                  onTap: () {
                    setState(() => _color = Color(c));
                    _saveFontConfig();
                    _scheduleRegen();
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color.toARGB32() == c
                            ? theme.colorScheme.primary
                            : Colors.white24,
                        width: _color.toARGB32() == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_s('位置', 'Position'), style: const TextStyle(fontSize: 13)),
          Row(
            children: [
              Expanded(
                child: RadioGroup<_TextPos>(
                  groupValue: _pos,
                  onChanged: (v) {
                    setState(() => _pos = v!);
                    _saveFontConfig();
                    _scheduleRegen();
                  },
                  child: Row(
                    children: [
                      for (final p in _TextPos.values)
                        Expanded(
                          child: RadioListTile<_TextPos>(
                            title: Text(switch (p) {
                              _TextPos.top => _s('顶部', 'Top'),
                              _TextPos.middle => _s('居中', 'Center'),
                              _TextPos.bottom => _s('底部', 'Bottom'),
                            }, style: const TextStyle(fontSize: 12)),
                            value: p,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(String label) => Text(
        label,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
      );

  Widget _buildTemplateCards(ThemeData theme) {
    final builtinEntries = TemplateGeneratorService.allSpecs
        .where((s) => s.category == _category)
        .map((s) => _Entry.builtin(s))
        .toList();

    final type = switch (_category) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
    final remoteEntries = _remoteEntries();
    final userEntries = _userTemplates
        .where((t) =>
            t.type == type &&
            !builtinEntries.any((b) => t.path.endsWith(b.key)) &&
            // A rendered catalogue template is registered like any other
            // template, so hide that duplicate — the card above already owns it.
            !remoteEntries.any((r) => t.path.contains(r.remote!.cacheKey)))
        .map((t) => _Entry.user(t))
        .toList();

    final cards = <Widget>[
      for (final e in [...builtinEntries, ...remoteEntries, ...userEntries])
        _buildCard(theme, e),
    ];
    if (_catalogNote != null) {
      cards.add(_buildCatalogNote(theme));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: cards);
  }

  /// Explains why the catalogue row is missing or stale. Shown as a card-sized
  /// note rather than an error banner: nothing is broken, something is
  /// unavailable.
  Widget _buildCatalogNote(ThemeData theme) {
    final offline = _remoteSpecs.isEmpty;
    return Container(
      width: 90,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(offline ? Icons.cloud_off_outlined : Icons.cloud_outlined,
              size: 20, color: Colors.white38),
          const SizedBox(height: 2),
          Text(
            offline
                ? _s('无在线模板', 'No online')
                : _s('离线缓存', 'Cached'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 8, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  /// Silently load the saved title for a template.
  ///
  /// The text field is shared by all three category tabs, so it must ALWAYS
  /// be re-set for the newly-selected entry — falling back to the localized
  /// placeholder when the entry has no saved title. Otherwise the previous
  /// category's text leaks into this tab (e.g. ending's title showing up on
  /// startup/transition after opening the editor on the ending tab).
  Future<void> _loadTemplateTitle(_Entry entry) async {
    final fallback = TemplateEditorDialog.defaultStartupTitle(
        ref.read(languageProvider));
    if (entry.userTemplate != null) {
      final text =
          TemplateEditorDialog.resolvePreviewText(entry.userTemplate, fallback);
      if (_textCtrl.text != text) {
        setState(() => _textCtrl.text = text);
      }
      return;
    }
    final cat = entry.spec?.category;
    if (cat == null) return;
    final type = switch (cat) {
      TemplateCategory.startup => TemplateType.startup,
      TemplateCategory.transition => TemplateType.transition,
      TemplateCategory.ending => TemplateType.ending,
    };
    final repo = ref.read(templateRepositoryProvider);
    final dir = TemplateGeneratorService.templatesDir;
    final templatePath = '$dir${Platform.pathSeparator}${entry.spec!.fileName}';
    final existing = await repo.listByType(type);
    final registered =
        existing.where((t) => t.path == templatePath).firstOrNull;

    final text =
        TemplateEditorDialog.resolvePreviewText(registered, fallback);
    if (_textCtrl.text != text) {
      setState(() => _textCtrl.text = text);
    }
    final saved = registered?.title;
    if (cat == TemplateCategory.startup && (saved == null || saved.isEmpty)) {
      // Embedded startup templates apply the placeholder as title by default.
      _saveTextAsTitle();
    }
  }

  /// Debounce-save the current preview text as the template title.
  ///
  /// The target entry and text are captured at schedule time: the user may
  /// switch category tabs before the timer fires, and the shared field /
  /// selection must not be read late (that would write one category's text
  /// into another category's template).
  void _saveTextAsTitle() {
    _titleSaveDebounce?.cancel();
    final target = _selected;
    final text = _textCtrl.text.trim();
    _titleSaveDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (text.isEmpty) return;
      final repo = ref.read(templateRepositoryProvider);
      Template? t = target.userTemplate;
      if (t == null && target.spec != null) {
        final spec = target.spec!;
        final dir = TemplateGeneratorService.templatesDir;
        final templatePath = '$dir${Platform.pathSeparator}${spec.fileName}';
        final type = switch (spec.category) {
          TemplateCategory.startup => TemplateType.startup,
          TemplateCategory.transition => TemplateType.transition,
          TemplateCategory.ending => TemplateType.ending,
        };
        final existing = await repo.listByType(type);
        t = existing.where((x) => x.path == templatePath).firstOrNull;
        t ??= await repo.save(Template(
          id: '',
          name: spec.label,
          path: templatePath,
          type: type,
        ));
      }
      if (t == null) return;

      if (t.title != text) await repo.save(t.copyWith(title: text));
      unawaited(_loadUserTemplates());
      ref.read(templateRefreshProvider.notifier).state++;
    });
  }

  Widget _buildCard(ThemeData theme, _Entry entry) {
    final selected = entry.key == _selected.key;
    return GestureDetector(
      onTap: () async {
        setState(() => _selected = entry);
        await _selectEntry(entry);
        await _applyFontConfig(entry);
        await _loadTemplateTitle(entry);
        _scheduleRegen(immediate: true);
      },
      child: Container(
        width: 90,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 80,
                height: 45,
                child: FutureBuilder<String?>(
                  future: _thumb(entry),
                  builder: (context, snap) {
                    final path = snap.data;
                    if (path != null) {
                      return Image.file(File(path), fit: BoxFit.cover);
                    }
                    return Container(
                      color: Colors.black38,
                      child: Icon(
                        entry.remote != null
                            ? Icons.cloud_download_outlined
                            : entry.userTemplate != null
                                ? Icons.person_outline
                                : Icons.movie_outlined,
                        size: 20,
                        color: Colors.white38,
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              entry.label
                  .replaceFirst(RegExp(r'^(Startup|Transition|Ending) '), ''),
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  /// Provenance line under the cards: where a catalogue template comes from and
  /// that its script is vetted before running. Without this the user cannot
  /// tell a downloaded template from a built-in one.
  Widget? _buildRemoteInfo(ThemeData theme) {
    final remote = _selected.remote;
    if (remote == null) return null;
    final author = remote.author.isEmpty ? '—' : remote.author;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, size: 12, color: Colors.white38),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${_s('在线模板', 'Online template')} · $author · '
              '${_s('脚本已通过安全校验', 'script passed policy check')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(_s('实时预览', 'Live Preview')),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_controller != null)
                      Center(
                        child: Video(
                          // New element per controller: media_kit's Video does
                          // not re-subscribe to a swapped controller, so a new
                          // key is required after switching templates.
                          key: ValueKey(_controller),
                          controller: _controller!,
                        ),
                      )
                    else
                      const Center(
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    if (_busy) ...[
                      const ColoredBox(color: Colors.black54),
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _status ?? _s('生成中…', 'Generating\u2026'),
                              style: const TextStyle(color: Colors.white70),
                            ),
                            if (_status != null && _progress > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${(_progress * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            '${_s('预览失败', 'Preview failed')}:\n$_error',
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, size: 20),
                tooltip: _muted ? _s('取消静音', 'Unmute') : _s('静音', 'Mute'),
                onPressed: _player == null
                    ? null
                    : () {
                        setState(() => _muted = !_muted);
                        _player!.setVolume(_muted ? 0 : 100);
                      },
              ),
              const SizedBox(width: 8),
              Text(
                _busy
                    ? (_status ?? _s('生成中…', 'Generating\u2026'))
                    : (_error != null ? _s('预览失败', 'Preview failed') : _s('循环播放中', 'Looping')),
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _restoreDefaults,
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(_s('恢复默认', 'Restore Defaults')),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_s('关闭', 'Close')),
          ),
        ],
      ),
    );
  }
}