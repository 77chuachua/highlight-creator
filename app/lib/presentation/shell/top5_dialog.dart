import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/data/top5_repository.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/top5_entry.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/data/voice_pack_store.dart';
import 'package:highlight_creator/domain/entities/voice_pack.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/presentation/shell/voice_pack_guide_dialog.dart';
import 'package:highlight_creator/services/error_logger.dart';
import 'package:highlight_creator/services/local_voice_service.dart';
import 'package:highlight_creator/services/top5_cache.dart';
import 'package:highlight_creator/services/voice_service.dart';
import 'package:highlight_creator/services/voice_take_store.dart';

/// Open the Top-5 flow. Weekly reels pick from the current project's clips,
/// monthly reels pick from this month's weekly reels, yearly ones from this
/// year's monthly reels — the same pyramid, one level at a time.
Future<void> openTop5Dialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    // Modal on purpose: picking and narrating five clips is a long flow and a
    // stray click next to the dialog used to close it and lose the work. The
    // dialog owns its exits (取消 / 关闭 / the header ✕).
    barrierDismissible: false,
    builder: (_) => const Top5Dialog(),
  );
}

/// One selectable clip: a timeslot window (weekly) or an existing entry's clip
/// (monthly/yearly).
class _Candidate {
  final String id;
  final String title;
  final String subtitle;
  final int rating;
  final String? clipPath;
  final String? sourcePath;
  final double start;
  final double duration;

  /// Place in the project (1-based). Zero for entries that did not come from a
  /// timeslot, such as last month's reel picks.
  final int index;

  /// Remote-camera slot: the slice gets the same zoom-in Make applies.
  final bool remote;
  final double? centerX;
  final double? centerY;

  /// The exact caption Make stamped on this slot ("01 xx助攻xx"). Reusing the
  /// rendered slice means painting over it, so the text has to be known.
  final String? caption;

  const _Candidate({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.rating = 0,
    this.clipPath,
    this.sourcePath,
    this.start = 0,
    this.duration = 0,
    this.index = 0,
    this.remote = false,
    this.centerX,
    this.centerY,
    this.caption,
  });
}

class Top5Dialog extends ConsumerStatefulWidget {
  const Top5Dialog({super.key});

  @override
  ConsumerState<Top5Dialog> createState() => _Top5DialogState();
}

class _Top5DialogState extends ConsumerState<Top5Dialog> {
  final Top5Repository _repo = Top5Repository();
  final List<_Candidate> _picked = <_Candidate>[];
  final Map<String, TextEditingController> _comments = {};

  Top5Level _level = Top5Level.week;
  Top5Kind _kind = Top5Kind.goal;
  int _step = 0;
  bool _busy = false;
  double _progress = 0;
  String _busyLabel = '';

  /// Set once a reel renders: the dialog stays open so it can be watched.
  String? _outputPath;

  /// The one preview player for the whole dialog, with its [VideoController].
  ///
  /// Pair them once and keep them for the dialog's life: media_kit binds the
  /// native video output to the [Player], so switching clips is only
  /// `player.open(Media(...))` on the same pair. Building a new pair per click
  /// (or letting a new [Video] widget mount on a fresh texture) is what left
  /// the pane black while the clock kept running — the audio/position follows
  /// the player, the picture follows the texture.
  Player? _previewPlayer;
  VideoController? _previewController;
  String? _previewPath;

  /// Identity of what the preview player holds, so clicking the same clip
  /// again only seeks/plays instead of re-slicing and re-opening it.
  String? _previewKey;

  /// Bumped per preview so a superseded one cannot write into the new one.
  int _previewSeq = 0;

  /// mpv's own error/warning stream, plus the last line it printed for the
  /// clip being opened. A black pane after a successful `open` leaves no
  /// exception anywhere, so this is the only evidence there is.
  final List<StreamSubscription<dynamic>> _previewSubs = [];
  String? _previewMpvProblem;

  /// Preview work in flight. Cutting a clip runs ffmpeg for a few seconds,
  /// and a button that looks dead reads as "the preview is broken".
  bool _previewBusy = false;
  String _previewLabel = '';
  String? _previewError;

  /// A failure the user has to see. Snackbars from this dialog land on the
  /// root Scaffold, which the dialog covers, so errors are drawn inside it.
  String? _dialogError;

  /// One cut per candidate at a time: two clicks used to race on the same
  /// output path, and the loser left a half-written clip behind.
  final Map<String, Future<String?>> _sliceJobs = {};
  String? _sliceError;

  /// Set when the ranking was filled from the reel already on disk, so the
  /// picker can say why it is not empty.
  bool _restoredFromCache = false;

  /// The take last heard per narration line, reused by the render. Cloning
  /// quality varies run to run, so the user rolls by auditioning and this keeps
  /// the roll that was actually liked.
  late final VoiceTakeStore _takes =
      VoiceTakeStore('${_voiceDir().path}${Platform.pathSeparator}takes');

  /// Seed for auditioning and for the no-take clone. 50 by default: the user
  /// types it, so a take they like can be asked for again by number (here and
  /// in the studio).
  static const int _defaultSeed = 50;
  static const int _seedMax = 4294967295;
  late final TextEditingController _seedController =
      TextEditingController(text: '$_defaultSeed');

  /// The seed to clone with, or null when the field is not a usable seed.
  int? get _seed {
    final value = int.tryParse(_seedController.text.trim());
    if (value == null || value < 0 || value > _seedMax) return null;
    return value;
  }

  /// Installed Windows voices and imported voice packs. [_voiceId] holds
  /// either a system voice id or `pack:<id>`.
  List<SystemVoice> _voices = const [];
  List<VoicePack> _packs = const [];
  String? _voiceId;
  Player? _voicePlayer;
  bool _voiceBusy = false;

  static String _packValue(VoicePack pack) => 'pack:${pack.id}';

  /// The pack behind the current selection, if any.
  VoicePack? get _selectedPack {
    final id = _voiceId;
    if (id == null || !id.startsWith('pack:')) return null;
    final wanted = id.substring(5);
    for (final pack in _packs) {
      if (pack.id == wanted) return pack;
    }
    return null;
  }

  /// Strings for the current language.
  AppStrings get _l10n => ref.read(l10nProvider);

  static const _gold = Color(0xFFF2B933);
  static const _ink = Color(0xFF0A0A0C);

  @override
  void initState() {
    super.initState();
    // The player/texture pair exists from the first frame. media_kit creates
    // the native video output asynchronously, and opening a clip before it
    // lands is one of the ways the pane ends up black while the clock runs.
    final player = Player();
    _previewPlayer = player;
    _previewController = VideoController(player);
    _watchPreviewPlayer(player);
    // The voice list comes from the platform, so it is read after the first
    // frame rather than during initState. The reel on disk is restored in the
    // same pass, so the picker opens on what was already made.
    Future.microtask(() {
      _loadVoices();
      _restoreFromCache();
    });
  }

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    _seedController.dispose();
    for (final sub in _previewSubs) {
      sub.cancel();
    }
    _previewSubs.clear();
    // The [VideoController] is released by the [Player] (media_kit registers
    // its dispose on `player.platform.release`), so one dispose frees the pair.
    _previewPlayer?.dispose();
    _previewPlayer = null;
    _previewController = null;
    _voicePlayer?.dispose();
    super.dispose();
  }

  /// Log whatever mpv says while a clip opens.
  ///
  /// A decoder or video-output failure is not an exception: mpv writes it to
  /// its log and keeps going, which is exactly the "black pane, nothing in the
  /// log" case. Every line is also kept in [_previewMpvProblem] so the failure
  /// can be reported with it.
  void _watchPreviewPlayer(Player player) {
    _previewSubs.add(player.stream.error.listen((text) {
      _previewMpvProblem = text;
      ErrorLogger.log('[top5] preview=mpv_error text=${_oneLine(text)}', null,
          source: 'top5');
    }));
    _previewSubs.add(player.stream.log.listen((entry) {
      final level = entry.level.toLowerCase();
      if (level != 'error' && level != 'fatal' && level != 'warn') return;
      final line = '[${entry.prefix}] ${entry.text}';
      _previewMpvProblem = line;
      ErrorLogger.log('[top5] preview=mpv level=$level text=${_oneLine(line)}',
          null,
          source: 'top5');
    }));
  }

  /// One line, short enough for the error log.
  static String _oneLine(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 300 ? flat : '${flat.substring(0, 300)}…';
  }

  /// A brand-new player/texture pair.
  ///
  /// Reused for the recovery path: a wedged video output or a hardware decoder
  /// that refused this file does not survive a fresh mpv instance, and a fresh
  /// instance is the only lever the app has.
  Player _freshPreviewPlayer() {
    final old = _previewPlayer;
    final player = Player();
    _watchPreviewPlayer(player);
    if (mounted) {
      setState(() {
        _previewPlayer = player;
        _previewController = VideoController(player);
        _previewPath = null;
        _previewKey = null;
      });
    } else {
      _previewPlayer = player;
      _previewController = VideoController(player);
      _previewPath = null;
      _previewKey = null;
    }
    if (old != null) {
      // After the frame that swaps the [Video] widget: tearing the old output
      // down first leaves the rebuilt widget pointing at a dead player.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(old.dispose().then((_) {}, onError: (Object _) {}));
      });
    }
    return player;
  }

  /// Whether the pane can actually show a picture.
  ///
  /// [Video] only draws once mpv reports a video size *and* the native output
  /// has handed it a texture id with a real (non 1×1) rect; anything short of
  /// that is a black rectangle after a perfectly successful `open()`. All three
  /// are polled because none of them raises an exception.
  Future<bool> _waitPreviewPicture(Player player) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final state = player.state;
      final controller = _previewController;
      final rect = controller?.rect.value;
      final decoded = (state.width ?? 0) > 0 && (state.height ?? 0) > 0;
      final textured = controller?.id.value != null &&
          rect != null &&
          rect.width > 2 &&
          rect.height > 2;
      if (decoded && textured) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  /// System voices plus imported packs. Empty only when the machine has no
  /// usable Chinese voice at all, which the guide dialog explains how to fix.
  Future<void> _loadVoices() async {
    final voices = await VoiceService.voices();
    // Fold a pre-pack recording into a pack before listing; idempotent.
    VoicePackStore().migrateLegacy(engine: LocalVoiceService.engineName);
    final packs = const VoicePackStore().list();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _packs = packs;
      final valid = voices.any((v) => v.id == _voiceId) ||
          packs.any((p) => _packValue(p) == _voiceId);
      if (!valid) {
        // Keep the picker on a value that exists, in preference order:
        // a pack (the whole point of the feature), then a system voice.
        _voiceId = packs.isNotEmpty
            ? _packValue(packs.first)
            : (voices.isEmpty ? null : voices.first.id);
      }
    });
  }

  /// Where the narration for a run is kept.
  ///
  /// TTS, clone and preview audio: all of it is mixed into the reel and
  /// re-synthesised next time, so it belongs under temp rather than next to
  /// the deliverables.
  Directory _voiceDir() {
    final dir = Directory('${AppPaths.tempDir}${Platform.pathSeparator}'
        '5best_narration');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Play a file through the preview player.
  Future<void> _playFile(String path) async {
    _voicePlayer ??= Player();
    await _voicePlayer!.open(Media(path));
    await _voicePlayer!.play();
  }

  /// File identity of one of the pack's audio files ('' when it is missing).
  String _packStamp(String path) {
    if (path.isEmpty) return '';
    try {
      final file = File(path);
      if (!file.existsSync()) return 'missing';
      final stat = file.statSync();
      return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return '';
    }
  }

  /// Everything a cloned take depends on. A take made from a different line or
  /// a different pack must never be rendered: the words would not match.
  String _takeSignature(VoicePack pack, String text) =>
      VoiceTakeStore.signature(
        packId: pack.id,
        text: text,
        speed: pack.speed,
        instruct: pack.instruct,
        promptText: pack.promptText,
        // Re-recording the pack changes these files, not the pack id.
        voice: '${_packStamp(pack.referencePath)}|'
            '${_packStamp(pack.stylePath ?? '')}',
      );

  /// Speak this clip's commentary with the selected voice.
  ///
  /// The button sits on every comment, so it is clear which line is heard.
  /// With the user's own voice selected, the recorded sample is played.
  Future<void> _previewVoice(_Candidate candidate) async {
    final voiceId = _voiceId;
    final pack = _selectedPack;
    if (pack != null) {
      // A voice pack: the local engine clones its reference, so any text can
      // be spoken in that voice.
      final own = _comments[candidate.id]?.text.trim() ?? '';
      if (own.isEmpty) {
        _fail(_l10n.top5NeedComment);
        return;
      }
      if (!LocalVoiceService.isInstalled) {
        _fail(_l10n.top5EngineNotInstalled);
        return;
      }
      if (!File(pack.referencePath).existsSync()) {
        _fail(_l10n.top5PackReferenceMissing(pack.name));
        return;
      }
      // No seed, no clone: the field is part of what the take means.
      final seed = _seed;
      if (seed == null) {
        _fail(_l10n.top5SeedInvalid);
        return;
      }
      setState(() => _voiceBusy = true);
      try {
        final signature = _takeSignature(pack, own);
        final result = await LocalVoiceService.speak(
          text: own,
          // The pack carries the transcript its reference was recorded with;
          // the guide text is only a fallback for older packs.
          promptText: pack.promptText.isEmpty
              ? VoiceService.personalVoicePrompt
              : pack.promptText,
          reference: pack.referencePath,
          prosodyReference: pack.stylePath,
          speed: pack.speed,
          instruct: pack.instruct,
          seed: seed,
          output: '${_voiceDir().path}${Platform.pathSeparator}'
              'clone_preview_${candidate.id}.wav',
        );
        if (!result.ok) {
          _fail(result.error ?? _l10n.top5CloneFailed);
          return;
        }
        // Keep the version that was just heard before playing it: the render
        // must not roll the dice again and replace a good line with a bad one.
        _takes.keep(candidate.id, signature, result.path!, seed: seed);
        await _playFile(result.path!);
      } finally {
        if (mounted) setState(() => _voiceBusy = false);
      }
      return;
    }
    final comment = _comments[candidate.id]?.text.trim() ?? '';
    if (comment.isEmpty) {
      _fail(_l10n.top5NeedComment);
      return;
    }
    if (voiceId == null) {
      _fail(_l10n.top5NeedVoice);
      return;
    }
    setState(() => _voiceBusy = true);
    try {
      final clip = await VoiceService.synthesize(
        text: comment,
        voiceId: voiceId,
        outputPath: '${_voiceDir().path}${Platform.pathSeparator}'
            'preview_${candidate.id}.wav',
      );
      if (clip == null || !mounted) return;
      await _playFile(clip.path);
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  /// Short message at the bottom of the dialog.
  ///
  /// Fine for "done" confirmations, never for errors: this dialog sits above
  /// the root Scaffold, so its snackbars are invisible.
  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Report a failure where it can actually be read, and keep a record.
  void _fail(String message) {
    ErrorLogger.log(message, null, source: 'top5');
    if (!mounted) return;
    setState(() => _dialogError = message);
  }

  /// Run the voice studio the plugin ships, then reload the pack list.
  ///
  /// The studio is a separate program on purpose: it owns the microphone, the
  /// waveform and the "listen before saving" loop, none of which belong in a
  /// modal dialog. Without it, the install guide is the useful destination.
  Future<void> _createVoicePack() async {
    final studio = LocalVoiceService.studioPath;
    if (studio == null || !File(studio).existsSync()) {
      // No plugin, or a plugin without the studio: say which, because the
      // guide alone looks like it is only about Windows voices.
      await openVoicePackGuideDialog(
        context,
        onRefresh: _loadVoices,
        warning: LocalVoiceService.isInstalled
            ? _l10n.top5StudioMissing
            : '${_l10n.top5EngineMissing} ${_l10n.top5EngineMissingHint}',
      );
      return;
    }
    try {
      // The studio records through ffmpeg, which lives with the app; pass the
      // path so the studio does not have to guess or find it on PATH.
      final ffmpeg = await VideoProcessingService.findFfmpeg();
      // Waiting for the studio to close is what makes the new pack appear
      // without the user hunting for a refresh button.
      final process = await Process.start('cmd', [
        '/c',
        studio,
        if (ffmpeg != null) ...['--ffmpeg', ffmpeg],
      ]);
      // Keep the tail of stderr: when the launcher dies instantly (a broken
      // .bat, a missing plugin python) the message is the only clue.
      final errors = StringBuffer();
      process.stderr.listen(
        (data) => errors.write(utf8.decode(data, allowMalformed: true)),
        onError: (_) {},
      );
      final code = await process.exitCode;
      if (!mounted) return;
      await _loadVoices();
      if (!mounted) return;
      if (code != 0) {
        final lines = errors
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        final detail = lines.isEmpty ? '' : ': ${lines.last.trim()}';
        _fail(_l10n.top5StudioLaunchFailed(code, detail));
        return;
      }
      _toast(_l10n.top5VoiceRefreshed);
    } catch (e) {
      ErrorLogger.log(e, null, source: 'voice-pack');
      _fail(_l10n.top5StudioStartError(e));
    }
  }

  /// Import a pack folder, or turn a single recording into one.
  Future<void> _importVoicePack() async {
    final mode = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_l10n.top5ImportTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('folder'),
            child: Text(_l10n.top5ImportFolder),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('audio'),
            child: Text(_l10n.top5ImportAudio),
          ),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    try {
      if (mode == 'folder') {
        final dir = await FilePicker.platform
            .getDirectoryPath(dialogTitle: _l10n.top5PickPackFolder);
        if (dir == null || !mounted) return;
        await _importFolder(dir);
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg'],
        );
        final path = picked?.files.single.path;
        if (path == null || !File(path).existsSync() || !mounted) return;
        await _importAudio(path);
      }
    } catch (e) {
      ErrorLogger.log(e, null, source: 'voice-pack');
      _fail(_l10n.top5ImportFailed(e));
    }
  }

  Future<void> _importFolder(String dir) async {
    final sep = Platform.pathSeparator;
    const store = VoicePackStore();
    // Already a pack: copy it as is.
    if (File('$dir$sep${VoicePack.referenceName}').existsSync()) {
      final pack = await store.importDirectory(dir,
          engine: LocalVoiceService.engineName);
      if (!mounted) return;
      if (pack == null) {
        _fail(_l10n.top5FolderNoAudio);
        return;
      }
      await _loadVoices();
      if (!mounted) return;
      setState(() => _voiceId = _packValue(pack));
      _toast(_l10n.top5Imported(pack.name));
      return;
    }
    // Otherwise it has to hold exactly one recording.
    const audio = ['.wav', '.mp3', '.m4a', '.aac', '.flac', '.ogg'];
    final files = Directory(dir)
        .listSync()
        .whereType<File>()
        .where((f) => audio.any((e) => f.path.toLowerCase().endsWith(e)))
        .toList();
    if (files.length != 1) {
      _fail(_l10n.top5FolderOneAudio);
      return;
    }
    await _importAudio(files.single.path);
  }

  /// Convert an arbitrary recording into a pack's reference.wav and import it.
  Future<void> _importAudio(String path) async {
    final sep = Platform.pathSeparator;
    final temp = Directory('${AppPaths.tempDir}${sep}pack_import');
    if (temp.existsSync()) temp.deleteSync(recursive: true);
    temp.createSync(recursive: true);
    final reference = '${temp.path}$sep${VoicePack.referenceName}';
    final service = VideoProcessingService(
      ffmpegPath: await VideoProcessingService.findFfmpeg(),
    );
    final result =
        await service.toVoiceWav(inputPath: path, outputPath: reference);
    if (result.exitCode != 0 || !File(reference).existsSync()) {
      _fail(_l10n.top5AudioConvertFailed(_ffmpegReason(result)));
      return;
    }
    final suggested = File(path)
        .uri
        .pathSegments
        .last
        .replaceAll(RegExp(r'\.[^.]+$'), '');
    final pack = await const VoicePackStore().importDirectory(
      temp.path,
      name: suggested,
      engine: LocalVoiceService.engineName,
    );
    if (!mounted) return;
    if (pack == null) {
      _fail(_l10n.top5ImportFailedShort);
      return;
    }
    await _loadVoices();
    if (!mounted) return;
    setState(() => _voiceId = _packValue(pack));
    _toast(_l10n.top5Imported(pack.name));
  }

  /// The take kept from the last audition, when it still matches this line.
  ///
  /// Two tiny stat/reads per card per build: a take is one wav plus its
  /// signature, and cards do not rebuild on every keystroke.
  VoiceTake? _takeFor(_Candidate candidate) {
    final pack = _selectedPack;
    final comment = _comments[candidate.id]?.text.trim() ?? '';
    if (pack == null || comment.isEmpty) return null;
    return _takes.find(candidate.id, _takeSignature(pack, comment));
  }

  /// Replay the take kept from the last audition.
  ///
  /// Nothing is cloned here: keeping the take is only useful if it can be heard
  /// again later, without rolling new dice.
  Future<void> _playTake(VoiceTake take) async {
    if (!File(take.path).existsSync()) {
      _fail(_l10n.top5TakeMissing);
      return;
    }
    try {
      await _playFile(take.path);
    } catch (e) {
      _fail(_l10n.top5PreviewFailed(e));
    }
  }

  /// What will be heard for this clip. [take] is [_takeFor] of the same card.
  String _narrationState(_Candidate candidate, VoiceTake? take) {
    final pack = _selectedPack;
    if (pack != null) {
      return take != null
          ? _l10n.top5NarrationPackCached(pack.name)
          : _l10n.top5NarrationPack(pack.name);
    }
    final comment = _comments[candidate.id]?.text.trim() ?? '';
    if (comment.isEmpty) return _l10n.top5NoComment;
    String? name;
    for (final voice in _voices) {
      if (voice.id == _voiceId) name = voice.name;
    }
    return _l10n.top5NarrationSystem(name ?? '');
  }

  /// Yearly reels stack ten clips; weekly and monthly reels stack five.
  int get _wantedCount => _level == Top5Level.year ? 10 : 5;

  String get _kindLabel =>
      _kind == Top5Kind.goal ? _l10n.top5KindGoal : _l10n.top5KindSave;

  String get _levelLabel => switch (_level) {
        Top5Level.week => '周',
        Top5Level.month => '月',
        Top5Level.year => '年',
      };

  /// The period anchor comes from the project, not the clock.
  ///
  /// A project recorded on Oct 21 belongs to week 43; reopening it on Oct 26
  /// (week 44) must not silently move the reel a week ahead. The project row's
  /// `createdAt` carries that date - loading an `.hlcproj` sets it from the
  /// file's `date` key or its name (see data/project_file.dart).
  DateTime get _projectDate {
    final project = ref.read(recordProvider).selectedProject;
    return project?.createdAt ?? DateTime.now();
  }

  /// "2026-W43 · 本周" only when it really is this week; otherwise just the key.
  String _periodLabel(DateTime date) {
    final now = DateTime.now();
    final key = top5PeriodKey(_level, date);
    final current = switch (_level) {
      Top5Level.week => top5WeekKey(now),
      Top5Level.month => top5MonthKey(now),
      Top5Level.year => top5YearKey(now),
    };
    if (key != current) return key;
    final suffix = switch (_level) {
      Top5Level.week => _l10n.top5ThisWeek,
      Top5Level.month => _l10n.top5ThisMonth,
      Top5Level.year => _l10n.top5ThisYear,
    };
    return '$key · $suffix';
  }

  /// Spelled out for the tooltip: which date the period was derived from.
  String _projectDateHint(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    final iso = '${date.year}-${two(date.month)}-${two(date.day)}';
    return _l10n.top5ProjectDateHint(iso);
  }

  String _introTitle(DateTime now) {
    final title = _l10n.top5ReelTitle(_wantedCount, _kindLabel);
    return switch (_level) {
      Top5Level.week => _l10n.top5IntroWeek(
          now.year, top5WeekKey(now).split('-W').last, title),
      Top5Level.month => _l10n.top5IntroMonth(now.year, now.month, title),
      Top5Level.year => _l10n.top5IntroYear(now.year, title),
    };
  }

  /// Candidates for the current level/kind. Weekly reels come from the open
  /// project's timeslots; the other two levels come from the reels below them.
  List<_Candidate> _candidates() {
    if (_level == Top5Level.week) {
      final record = ref.read(recordProvider);
      final sources = record.selectedProject?.sources ?? const [];
      final byName = <String, String>{
        for (final s in sources)
          s.filePath.split(RegExp(r'[\\/]')).last: s.filePath,
      };
      // Project order, not rating order: the list is scanned by number, so the
      // numbers have to run 1, 2, 3 … down the panel.
      return [
        for (var i = 0; i < record.timeslots.length; i++)
          _candidateOfSlot(record.timeslots[i], i + 1, byName),
      ];
    }
    final now = _projectDate;
    final entries = _level == Top5Level.month
        ? _repo.weeklyCandidates(_kind, now)
        : _repo.monthlyCandidates(_kind, now);
    // Only offer entries whose clip still exists. Entries from a run whose
    // clips were deleted, or left over from an earlier (wrong-period) run,
    // listed a second identical set that could never be picked - and failed
    // three steps later if it was.
    final usable = [
      for (final e in entries)
        if (e.clipPath.isNotEmpty && File(e.clipPath).existsSync()) e,
    ];
    final missing = entries.length - usable.length;
    if (missing > 0) {
      ErrorLogger.log(
          '[top5] 跳过 $missing 个片段文件已丢失的$_levelLabel度条目', null,
          source: 'top5');
    }
    return [
      for (final e in usable)
        _Candidate(
          id: e.id,
          title: e.title.trim().isEmpty ? e.periodKey : e.title.trim(),
          subtitle: '${e.periodKey} · NO.${e.rank}',
          clipPath: e.clipPath,
        ),
    ];
  }

  _Candidate _candidateOfSlot(
      Timeslot slot, int position, Map<String, String> byName) {
    final window = VideoProcessingService.slotWindow(slot);
    final description = slot.description.trim();
    return _Candidate(
      id: slot.id,
      index: position,
      title: description.isEmpty ? _l10n.top5ClipFallback(position) : description,
      subtitle: _l10n.top5ClipWindow(window.start.toStringAsFixed(1),
          '${window.duration.toStringAsFixed(1)}s'),
      rating: slot.rating,
      sourcePath: byName[slot.filename] ?? slot.filename,
      start: window.start,
      duration: window.duration,
      remote: slot.remote,
      centerX: slot.centerX,
      centerY: slot.centerY,
      // Same index and description Make used, so the caption matches the
      // pixels that were burned into results/slot_<i>_sub.mp4.
      caption: VideoProcessingService.slotCaption(position - 1, slot.description),
    );
  }

  void _toggle(_Candidate candidate) {
    setState(() {
      final index = _picked.indexWhere((c) => c.id == candidate.id);
      if (index >= 0) {
        _picked.removeAt(index);
        _comments.remove(candidate.id)?.dispose();
      } else if (_picked.length < _wantedCount) {
        _picked.add(candidate);
        _comments.putIfAbsent(candidate.id, TextEditingController.new);
      }
    });
  }

  void _remove(int index) {
    setState(() {
      final removed = _picked.removeAt(index);
      _comments.remove(removed.id)?.dispose();
    });
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _picked.length) return;
    setState(() => _picked.insert(to, _picked.removeAt(from)));
  }

  void _switchTo({Top5Level? level, Top5Kind? kind}) {
    setState(() {
      if (level != null) _level = level;
      if (kind != null) _kind = kind;
      _picked.clear();
      for (final c in _comments.values) {
        c.dispose();
      }
      _comments.clear();
      _restoredFromCache = false;
    });
    // The bucket just switched to may already have a reel on disk.
    _restoreFromCache();
  }

  /// Fill the ranking and the narration copy from the reel already on disk.
  ///
  /// "Make the Top 5" is a long flow and the render can fail half-way, so the
  /// clips it wrote are the deliverable: reopening the dialog (or coming back
  /// to this level/kind) must not ask for the same picks and the same wording
  /// again. Step 2 then shows the restored comments, ready to regenerate.
  void _restoreFromCache() {
    if (_picked.isNotEmpty || !mounted) return;
    final periodKey = top5PeriodKey(_level, _projectDate);
    List<Top5CachedPick> cached;
    try {
      cached = Top5Cache.picks(
        clipsDir: _clipsDir(),
        repo: _repo,
        level: _level,
        kind: _kind,
        periodKey: periodKey,
        wanted: _wantedCount,
      );
    } catch (e) {
      // Nothing the user can act on: the dialog simply starts empty.
      ErrorLogger.log(e, null, source: 'top5');
      return;
    }
    if (cached.isEmpty || !mounted) return;
    // Rows the pool still offers keep their preview/slice path; a slot whose
    // source is gone (project re-imported, parent reel deleted) is restored
    // from its own clip, which is what the render needs anyway.
    final pool = {for (final c in _candidates()) c.id: c};
    setState(() {
      for (final pick in cached) {
        final candidate =
            pool[pick.sourceId] ?? _candidateOfCache(pick, periodKey);
        _picked.add(candidate);
        final controller =
            _comments.putIfAbsent(candidate.id, TextEditingController.new);
        // Never overwrite something the user already typed.
        if (controller.text.trim().isEmpty && pick.comment.trim().isNotEmpty) {
          controller.text = pick.comment;
        }
      }
      _restoredFromCache = true;
    });
    ErrorLogger.log(
        '[top5] cache=hit level=${_level.name} kind=${_kind.name} '
        'period=$periodKey picks=${cached.length}',
        null,
        source: 'top5');
  }

  /// A restored slot that the picker no longer offers: its own clip is both the
  /// preview and the render input. Its recorded source id is kept as the
  /// candidate id, so a re-render writes the same row again.
  _Candidate _candidateOfCache(Top5CachedPick pick, String periodKey) {
    return _Candidate(
      id: pick.sourceId.isNotEmpty
          ? pick.sourceId
          : 'cached_${_level.name}_${periodKey}_${_kind.name}_${pick.rank}',
      title: pick.title.isEmpty
          ? _l10n.top5ClipFallback(pick.rank)
          : pick.title,
      subtitle: '$periodKey · NO.${pick.rank}',
      clipPath: pick.clipPath,
    );
  }

  /// The clips a reel owns, one file per rank.
  ///
  /// These are the deliverable fragments: a monthly reel picks from the weekly
  /// copies, so a weekly reel (or its source video) can be deleted without
  /// breaking the reel above it.
  Directory _clipsDir() {
    final dir =
        Directory('${AppPaths.baseDir}${Platform.pathSeparator}5best_clips');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The slice cache: one cut per slot, rebuilt on demand and read by nothing
  /// afterwards, so it stays under temp and clearing temp is safe.
  Directory _sliceCacheDir() {
    final dir = Directory('${AppPaths.tempDir}${Platform.pathSeparator}'
        '5best_slices');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// A silent, text-free clip for one pick, cached so preview and generate
  /// share one encode. Existing entries already carry their own copy.
  ///
  /// Concurrent calls for the same candidate share one cut instead of racing
  /// on the same output file.
  Future<String?> _sliceClip(_Candidate candidate) {
    return _sliceJobs.putIfAbsent(
        candidate.id, () => _sliceClipOnce(candidate));
  }

  Future<String?> _sliceClipOnce(_Candidate candidate) async {
    try {
      return await _sliceClipInner(candidate);
    } finally {
      _sliceJobs.remove(candidate.id);
    }
  }

  Future<String?> _sliceClipInner(_Candidate candidate) async {
    _sliceError = null;
    if (candidate.sourcePath == null) {
      final clip = candidate.clipPath;
      if (clip != null && await _isPlayable(clip)) return clip;
      _sliceError = _l10n.top5ClipNoVideo;
      return null;
    }
    // The zoom flag is part of the cache key: a plain slice cached before the
    // remote filter existed would otherwise be reused without it.
    final out = '${_sliceCacheDir().path}${Platform.pathSeparator}'
        'src_${candidate.id}${candidate.remote ? '_zoom' : ''}.mp4';
    // Existence is not proof of anything: a cut interrupted half-way leaves a
    // stub that ffprobe rejects, and serving that stub is why the same clip
    // could never preview again while its neighbours were fine.
    if (await _isPlayable(out)) return out;

    final service = VideoProcessingService(
      ffmpegPath: await VideoProcessingService.findFfmpeg(),
    );

    // Make already cut this slot once. Reuse its slice instead of decoding the
    // source again; the caption it burned in gets painted over.
    final rendered = await _makeSliceFor(candidate);
    if (rendered != null) {
      final masked = await service.maskCaptionWatermark(
        sourcePath: rendered,
        outputPath: out,
        caption: candidate.caption ?? '',
      );
      if (masked.exitCode == 0 && await _isPlayable(out)) {
        return out;
      }
      _sliceError = _ffmpegReason(masked);
      // Fall through: cutting from the source still gets the user a clip.
    }

    final res = await service.materializeTop5Clip(
      sourcePath: candidate.sourcePath!,
      outputPath: out,
      startSecs: candidate.start,
      durationSecs: candidate.duration,
      remote: candidate.remote,
      centerX: candidate.centerX,
      centerY: candidate.centerY,
    );
    if (res.exitCode != 0) {
      _sliceError = _ffmpegReason(res);
      return null;
    }
    if (!await _isPlayable(out)) {
      _sliceError = _l10n.top5SliceUnplayable;
      return null;
    }
    return out;
  }

  /// The slice Make already rendered for this slot, when it is still the right
  /// one.
  ///
  /// Make names these by position in the project (`slot_<i>_sub.mp4`), so a
  /// reordered project can leave an unrelated clip under that name. The
  /// duration has to match the slot's own window before the file is trusted.
  Future<String?> _makeSliceFor(_Candidate candidate) async {
    if (candidate.index <= 0) return null;
    final path = '${AppPaths.resultsDir}${Platform.pathSeparator}'
        'slot_${candidate.index - 1}_sub.mp4';
    if (!await _isPlayable(path)) return null;
    final ms = await VideoProcessingService.probeDurationMs(path);
    if (ms == null) return null;
    final wanted = (candidate.duration * 1000).round();
    return (ms - wanted).abs() <= 1000 ? path : null;
  }

  /// Whether a file is a video the player can actually open.
  Future<bool> _isPlayable(String path) async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) return false;
    final ms = await VideoProcessingService.probeDurationMs(path);
    return ms != null && ms > 0;
  }

  /// The last meaningful line ffmpeg printed, so the dialog can say what went
  /// wrong instead of doing nothing.
  String _ffmpegReason(ProcessResult res) {
    final text = '${res.stderr}'.trim();
    if (text.isEmpty) return _l10n.top5SliceFailed(res.exitCode);
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? _l10n.top5SliceFailedShort : lines.last.trim();
  }

  /// What identifies the clip in the preview player. Slot id plus the source
  /// file and the exact cut: a re-picked or re-ordered slot is a different
  /// clip even though it may share an id.
  static String _previewKeyOf(_Candidate candidate) => <String>[
        candidate.id,
        candidate.sourcePath ?? candidate.clipPath ?? '',
        candidate.start.toStringAsFixed(3),
        candidate.duration.toStringAsFixed(3),
        candidate.remote ? 'zoom' : '',
      ].join('|');

  Future<void> _preview(_Candidate candidate) async {
    // One preview at a time: while a clip is being prepared the player is
    // mid-`open`, so a second tap must not fight it.
    if (_previewBusy) return;

    final key = _previewKeyOf(candidate);

    // Same clip as the one already loaded: play it, do not prepare it again.
    // Re-slicing here cost an ffprobe, a 「准备片段」 flash and a re-open of the
    // file the player was already showing. A pane that reported no picture is
    // not "already loaded": it has to go through the recovery path below.
    if (key == _previewKey &&
        _previewPlayer != null &&
        _previewPath != null &&
        _previewError == null) {
      final player = _previewPlayer!;
      try {
        // A finished clip starts over; a paused one resumes where it stopped.
        if (player.state.completed) await player.seek(Duration.zero);
        await player.play();
        if (mounted && _previewError != null) {
          setState(() => _previewError = null);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _previewError = _l10n.top5PreviewFailed(e));
        _fail(_l10n.top5PreviewFailed(e));
      }
      return;
    }

    final seq = ++_previewSeq;
    _previewMpvProblem = null;

    // The pair already exists (initState created it); the widget is attached
    // to the controller from the first frame, so only the media changes here.
    var player = _previewPlayer ?? _freshPreviewPlayer();
    _previewController ??= VideoController(player);

    setState(() {
      _previewBusy = true;
      _previewError = null;
      _previewLabel = _l10n.top5PreparingClip;
    });
    try {
      final path = await _sliceClip(candidate);
      if (!mounted || seq != _previewSeq) return;
      if (path == null) {
        final reason = _sliceError ?? _l10n.top5ClipNoPreview;
        setState(() => _previewError = reason);
        _fail(_l10n.top5PreviewFailed(reason));
        return;
      }
      setState(() => _previewLabel = _l10n.top5LoadingPlayer);
      ErrorLogger.log('[top5] preview=open seq=$seq path=$path clip=${candidate.id}',
          null,
          source: 'top5');

      // Stop the old clip first: opening while the previous `play()` is still
      // in flight races two media on one output.
      await player.pause();
      if (!mounted || seq != _previewSeq) return;
      await player.open(Media(path));
      if (!mounted || seq != _previewSeq) return;
      await player.play();
      if (!mounted || seq != _previewSeq) return;

      var healthy = await _waitPreviewPicture(player);
      if (!healthy) _logPreviewState('no_picture', seq, path, player, 0);

      // One retry on a fresh mpv instance: the failures that survive a good
      // `open()` (wedged video output, a hardware decoder that refused this
      // file) are per-instance, and re-creating the player is what clears them.
      if (!healthy && mounted && seq == _previewSeq) {
        setState(() => _previewLabel = _l10n.top5ReloadingPlayer);
        player = _freshPreviewPlayer();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted || seq != _previewSeq) return;
        await player.open(Media(path));
        if (!mounted || seq != _previewSeq) return;
        await player.play();
        if (!mounted || seq != _previewSeq) return;
        healthy = await _waitPreviewPicture(player);
        if (healthy) {
          ErrorLogger.log(
              '[top5] preview=recovered seq=$seq path=$path retry=1 mpv=${_oneLine(_previewMpvProblem ?? '')}',
              null,
              source: 'top5');
        } else {
          _logPreviewState('black', seq, path, player, 1);
        }
      }

      if (!mounted || seq != _previewSeq) return;
      if (!healthy) {
        setState(() => _previewError = _l10n.top5PreviewNoPicture);
        _fail(_l10n.top5PreviewNoPicture);
        return;
      }
      final state = player.state;
      ErrorLogger.log(
          '[top5] preview=ok seq=$seq path=$path w=${state.width} h=${state.height} '
          'dur=${state.duration.inMilliseconds}',
          null,
          source: 'top5');
      setState(() {
        _previewPath = path;
        _previewKey = key;
        _previewError = null;
      });
    } catch (e) {
      if (!mounted || seq != _previewSeq) return;
      // Say what failed inside the pane: a silent black frame is what made
      // "no picture" impossible to report.
      ErrorLogger.log('[top5] preview=failed seq=$seq error=$e', null,
          source: 'top5');
      setState(() => _previewError = _l10n.top5PreviewFailed(e));
      _fail(_l10n.top5PreviewFailed(e));
    } finally {
      if (mounted && seq == _previewSeq) {
        setState(() => _previewBusy = false);
      }
    }
  }

  /// Log why a preview has no picture: the clip, mpv's state and its own last
  /// complaint. This is the line that makes the next black screen explainable.
  void _logPreviewState(
      String outcome, int seq, String path, Player player, int retries) {
    final state = player.state;
    final controller = _previewController;
    final rect = controller?.rect.value;
    ErrorLogger.log(
        '[top5] preview=$outcome seq=$seq retry=$retries path=$path '
        'w=${state.width} h=${state.height} '
        'dur=${state.duration.inMilliseconds} '
        'completed=${state.completed} buffering=${state.buffering} '
        'video=${state.videoParams.pixelformat} '
        'texture=${controller?.id.value} '
        'rect=${rect?.width}x${rect?.height} '
        'mpv=${_oneLine(_previewMpvProblem ?? '')}',
        null,
        source: 'top5');
  }

  /// The background-music template the highlight reel uses ("直接使用集锦模板
  /// 中的 background music"). Relative registry paths resolve against the
  /// project root the same way Make does it.
  Future<String> _resolveBgm() async {
    final templates = ref.read(templateRepositoryProvider);
    final selected =
        ref.read(selectedTemplatesProvider)[TemplateType.backgroundMusic];
    Template? template;
    if (selected != null) template = await templates.getById(selected);
    if (template == null) {
      final list = await templates.listByType(TemplateType.backgroundMusic);
      if (list.isNotEmpty) template = list.first;
    }
    final raw = template?.path ?? '';
    if (raw.isEmpty) {
      throw StateError(_l10n.top5NeedBgm);
    }
    final direct = File(raw);
    if (direct.isAbsolute && direct.existsSync()) return raw;
    var dir = Directory.current;
    while (true) {
      final candidate = File('${dir.path}${Platform.pathSeparator}$raw');
      if (candidate.existsSync()) return candidate.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    throw StateError(_l10n.top5BgmMissing(raw));
  }

  /// Every slot owns its own copy: deleting a weekly reel (or its source video)
  /// must not break the monthly reel that picked it.
  Future<String> _storeClip(
      _Candidate candidate, int rank, String periodKey) async {
    // The kind belongs in the name: a goal reel and a save reel of the same
    // week used to write the same five files, so the second run silently
    // overwrote the first one's clips.
    final out = '${_clipsDir().path}${Platform.pathSeparator}'
        '${_level.name}_${periodKey}_${_kind.name}_$rank.mp4';
    final source = await _sliceClip(candidate);
    if (source == null || !File(source).existsSync()) {
      throw StateError(_l10n.top5ClipSliceFailed(candidate.title));
    }
    if (source == out) return out;
    File(source).copySync(out);
    return out;
  }

  Future<void> _generate() async {
    if (_picked.length != _wantedCount) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _busyLabel = _l10n.top5BusyPrepare;
    });
    try {
      final now = _projectDate;
      final periodKey = top5PeriodKey(_level, now);
      final service = VideoProcessingService(
        ffmpegPath: await VideoProcessingService.findFfmpeg(),
      );
      // Narrate every clip that has a comment, with the chosen voice.
      // Runs first: the entries below store the narration path.
      final narrationPaths = <String>[];
      final narrationDurations = <double>[];
      final voiceId = _voiceId;
      final pack = _selectedPack;
      for (var i = 0; i < _picked.length; i++) {
        final candidate = _picked[i];
        final comment = _comments[candidate.id]?.text.trim() ?? '';
        // A voice pack: the local engine clones its reference, so the comment
        // is spoken in that voice.
        if (comment.isNotEmpty && pack != null) {
          if (!LocalVoiceService.isInstalled) {
            throw StateError(_l10n.top5EngineNotInstalled);
          }
          // The last audition is the take the user picked. Cloning here again
          // would roll the dice once more and could trade a good line for a bad
          // one, which is exactly what auditioning was for.
          final take = _takes.find(candidate.id, _takeSignature(pack, comment));
          if (take != null) {
            if (mounted) {
              setState(() => _busyLabel =
                  _l10n.top5BusyTake(i + 1, _picked.length));
            }
            narrationPaths.add(take.path);
            final ms = await VideoProcessingService.probeDurationMs(take.path) ?? 0;
            narrationDurations.add(ms / 1000.0);
            continue;
          }
          // Cloning without a take needs a seed; the stored take above does not.
          final seed = _seed;
          if (seed == null) {
            throw StateError(_l10n.top5SeedInvalid);
          }
          if (mounted) setState(() => _busyLabel = _l10n.top5BusyClone(i + 1, _picked.length));
          final result = await LocalVoiceService.speak(
            text: comment,
            promptText: pack.promptText.isEmpty
                ? VoiceService.personalVoicePrompt
                : pack.promptText,
            reference: pack.referencePath,
            prosodyReference: pack.stylePath,
            speed: pack.speed,
            instruct: pack.instruct,
            seed: seed,
            output: '${_voiceDir().path}${Platform.pathSeparator}'
                'clone_${candidate.id}.wav',
          );
          if (!result.ok) {
            throw StateError(result.error ?? _l10n.top5CloneFailed);
          }
          narrationPaths.add(result.path!);
          final ms = await VideoProcessingService.probeDurationMs(result.path!) ?? 0;
          narrationDurations.add(ms / 1000.0);
          continue;
        }
        if (comment.isEmpty || voiceId == null) {
          narrationPaths.add('');
          narrationDurations.add(0);
          continue;
        }
        if (mounted) setState(() => _busyLabel = _l10n.top5BusySynth(i + 1, _picked.length));
        final clip = await VoiceService.synthesize(
          text: comment,
          voiceId: voiceId,
          outputPath: '${_voiceDir().path}${Platform.pathSeparator}'
              '${candidate.id}.wav',
        );
        narrationPaths.add(clip?.path ?? '');
        narrationDurations.add(
            (clip?.duration.inMilliseconds ?? 0) / 1000.0);
      }

      final clips = <String>[];
      final titles = <String>[];
      final entries = <Top5Entry>[];
      for (var i = 0; i < _picked.length; i++) {
        final candidate = _picked[i];
        final rank = i + 1;
        if (mounted) setState(() => _busyLabel = _l10n.top5BusyClip(rank, 5));
        final clipPath = await _storeClip(candidate, rank, periodKey);
        clips.add(clipPath);
        titles.add(candidate.title);
        entries.add(Top5Entry(
          id: '${_level.name}_${periodKey}_${_kind.name}_$rank',
          level: _level,
          kind: _kind,
          periodKey: periodKey,
          rank: rank,
          clipPath: clipPath,
          title: candidate.title,
          comment: _comments[candidate.id]?.text ?? '',
          narrationPath: narrationPaths[i],
          sourceTimeslotId: _level == Top5Level.week ? candidate.id : '',
          parentId: _level == Top5Level.week ? '' : candidate.id,
          createdAt: now,
        ));
      }

      final bgm = await _resolveBgm();
      // Record the reel before rendering it: the clips and the narration copy
      // are already on disk, and a render that dies half-way must not also lose
      // the ranking and the wording the user typed. Reopening the dialog
      // restores from these rows (see _restoreFromCache).
      _repo.replaceReel(_level, _kind, periodKey, entries);
      final outDir =
          Directory('${AppPaths.resultsDir}${Platform.pathSeparator}best5');
      if (!outDir.existsSync()) outDir.createSync(recursive: true);
      final outputPath = '${outDir.path}${Platform.pathSeparator}'
          '${periodKey}_${_kind.name}_top${_wantedCount}.mp4';
      if (mounted) setState(() => _busyLabel = _l10n.top5BusyRender(_l10n.top5ReelTitle(_wantedCount, _kindLabel)));
      await service.makeTop5(
        clipPaths: clips,
        titles: titles,
        introTitle: _introTitle(now),
        badge: _l10n.top5IntroBadge(_wantedCount,
            _l10n.top5ReelTitle(_wantedCount, _kindLabel), periodKey),
        outputPath: outputPath,
        bgMusicPath: bgm,
        narrationPaths: narrationPaths,
        narrationDurations: narrationDurations,
        endTitle: _l10n.top5ReelTitle(_wantedCount, _kindLabel),
        endSubtitle: _l10n.top5NextTime,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      // Stay open: the useful next step is watching the reel, not dismissing.
      setState(() {
        _busy = false;
        _progress = 1;
        _outputPath = outputPath;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_l10n.top5SavedTo(outputPath)),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      _fail(_l10n.top5GenerateFailed(e));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width < 1180 ? size.width - 40 : 1140,
        height: size.height < 760 ? size.height - 40 : 720,
        child: Column(
          children: [
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: _step == 0 ? _buildPicker(context) : _buildEditor(context),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _gold.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.emoji_events_outlined, size: 18, color: _gold),
          ),
          const SizedBox(width: 10),
          Text(_l10n.top5Title, style: theme.textTheme.titleMedium),
          const SizedBox(width: 18),
          _stepChip('1', _l10n.top5StepSelect, _step == 0),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 14, color: Colors.white24),
          const SizedBox(width: 6),
          _stepChip('2', _l10n.top5StepPreview, _step == 1),
          const Spacer(),
          IconButton(
            tooltip: _l10n.commonClose,
            // The dialog is modal, so this is the only way out. It stays live
            // while a reel renders: closing does not stop the render, and
            // _generate() records the reel and guards every setState with
            // `mounted`, so nothing is lost except the progress feedback.
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _stepChip(String number, String label, bool active) {
    final color = active ? _gold : Colors.white38;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.2),
          ),
          child: Text(number,
              style: TextStyle(fontSize: 10, color: color, height: 1)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  // ---------------------------------------------------------------- step 1
  Widget _buildPicker(BuildContext context) {
    final theme = Theme.of(context);
    final candidates = _candidates();
    final now = _projectDate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SegmentedButton<Top5Level>(
                // A selected segment grows a checkmark, which reflows every
                // segment and nudges the panels below it. The tinted fill
                // already shows the active one.
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                      value: Top5Level.week, label: Text(_l10n.top5LevelWeek)),
                  ButtonSegment(
                      value: Top5Level.month, label: Text(_l10n.top5LevelMonth)),
                  ButtonSegment(
                      value: Top5Level.year, label: Text(_l10n.top5LevelYear)),
                ],
                selected: {_level},
                onSelectionChanged:
                    _busy ? null : (v) => _switchTo(level: v.first),
              ),
              const SizedBox(width: 12),
              SegmentedButton<Top5Kind>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                      value: Top5Kind.goal, label: Text(_l10n.top5KindGoal)),
                  ButtonSegment(
                      value: Top5Kind.save, label: Text(_l10n.top5KindSave)),
                ],
                selected: {_kind},
                onSelectionChanged:
                    _busy ? null : (v) => _switchTo(kind: v.first),
              ),
              const SizedBox(width: 16),
              Tooltip(
                message: _projectDateHint(now),
                child: Text(_periodLabel(now),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
              // Why the ranking is already full: the reel for this period is on
              // disk. Saying so beats a dialog that looks pre-filled by magic.
              if (_restoredFromCache) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(24),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withAlpha(70)),
                  ),
                  child: Text(
                    _l10n.top5RestoredCache(
                        top5PeriodKey(_level, now), _picked.length),
                    style: TextStyle(
                        fontSize: 11, color: Colors.greenAccent.shade100),
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _picked.length == _wantedCount
                      ? Colors.green.withAlpha(40)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _l10n.top5Picked(_picked.length, _wantedCount),
                  style: TextStyle(
                    fontSize: 12,
                    color: _picked.length == _wantedCount
                        ? Colors.greenAccent.shade200
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _poolPanel(theme, candidates)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _lineupPanel(theme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _poolPanel(ThemeData theme, List<_Candidate> candidates) {
    return _panel(
      theme,
      title: _l10n.top5PoolTitle,
      trailing: _l10n.top5PoolCount(candidates.length),
      child: candidates.isEmpty
          ? _emptyState(
              theme,
              icon: Icons.video_library_outlined,
              // A new project has no slots, and monthly/yearly reels do not
              // need any: say where the clips come from instead of dead-ending.
              text: switch (_level) {
                Top5Level.week => _l10n.top5PoolEmptyWeek,
                Top5Level.month => _l10n.top5PoolEmptyMonth,
                Top5Level.year => _l10n.top5PoolEmptyYear,
              },
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: candidates.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.white.withAlpha(8)),
              itemBuilder: (context, index) =>
                  _poolRow(theme, candidates[index]),
            ),
    );
  }

  Widget _poolRow(ThemeData theme, _Candidate candidate) {
    final pickedIndex = _picked.indexWhere((c) => c.id == candidate.id);
    final picked = pickedIndex >= 0;
    final full = _picked.length >= 5 && !picked;
    return InkWell(
      onTap: _busy || full ? null : () => _toggle(candidate),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: candidate.rating > 0
                  ? Text(
                      '★' * candidate.rating + '☆' * (5 - candidate.rating),
                      style: const TextStyle(fontSize: 11, color: _gold),
                    )
                  : const Icon(Icons.archive_outlined,
                      size: 14, color: Colors.white24),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      candidate.index > 0
                          ? '${candidate.index} ${candidate.title}'
                          : candidate.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  Text(candidate.subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (picked)
              _rankBadge(pickedIndex + 1)
            else
              Icon(
                full ? Icons.block : Icons.add_circle_outline,
                size: 18,
                color: full ? Colors.white24 : theme.colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _lineupPanel(ThemeData theme) {
    return _panel(
      theme,
      title: _l10n.top5RanksTitle,
      trailing: _l10n.top5RanksHint,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (var i = 0; i < _wantedCount; i++)
            i < _picked.length
                ? _lineupRow(theme, i)
                : Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        _slotCircleEmpty(i + 1),
                        const SizedBox(width: 10),
                        Text(_l10n.cacheEmpty,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _lineupRow(ThemeData theme, int index) {
    final candidate = _picked[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          _rankBadge(index + 1),
          const SizedBox(width: 10),
          Expanded(
            child: Text(candidate.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
          _tinyIconButton(
            tooltip: _l10n.top5MoveUp,
            icon: Icons.arrow_upward,
            onPressed: index == 0 ? null : () => _move(index, index - 1),
          ),
          _tinyIconButton(
            tooltip: _l10n.top5MoveDown,
            icon: Icons.arrow_downward,
            onPressed: index == _picked.length - 1
                ? null
                : () => _move(index, index + 1),
          ),
          _tinyIconButton(
            tooltip: _l10n.top5Remove,
            icon: Icons.close,
            onPressed: () => _remove(index),
          ),
        ],
      ),
    );
  }

  Widget _tinyIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
    );
  }

  Widget _rankBadge(int rank) {
    final color = rank == 1 ? _gold : const Color(0xFFE2342B);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(40),
        border: Border.all(color: color, width: 1),
      ),
      child: Text('$rank',
          style: TextStyle(fontSize: 11, color: color, height: 1)),
    );
  }

  Widget _slotCircleEmpty(int slot) => Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Text('$slot',
            style: const TextStyle(fontSize: 10, color: Colors.white24)),
      );

  /// Seed picker for the cloned narration.
  ///
  /// The engine reseeds before every request, so this number *is* which take you
  /// get: the same seed and text give the same audio back. It is also what the
  /// take badge shows, which is how a liked style is reproduced in the studio.
  Widget _buildSeedRow(ThemeData theme) {
    final invalid = _seed == null;
    return Row(
      children: [
        const SizedBox(width: 2),
        Text(_l10n.top5Seed,
            style: TextStyle(
                fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          height: 34,
          child: TextField(
            controller: _seedController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 12),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              hintText: '$_defaultSeed',
              filled: true,
              fillColor: _ink,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                    color: invalid ? Colors.red.shade300 : Colors.white12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            invalid ? '⚠ ${_l10n.top5SeedInvalid}' : _l10n.top5SeedRange,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: invalid ? Colors.red.shade300 : Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- step 2
  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildVoiceRow(theme),
          if (_selectedPack != null) ...[
            const SizedBox(height: 8),
            _buildSeedRow(theme),
          ],
          if (_dialogError != null) ...[
            const SizedBox(height: 8),
            _errorStrip(),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.black,
                // The [Video] widget stays mounted for the dialog's life and
                // points at the current [VideoController]: switching clips only
                // opens a new Media under it. The key follows the controller,
                // because the recovery path swaps in a fresh pair and a stale
                // [Video] state would keep listening to the disposed player.
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_previewController == null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _emptyState(
                          theme,
                          icon: Icons.play_circle_outline,
                          text: _l10n.top5PreviewHint,
                          dark: true,
                        ),
                      )
                    else
                      Video(
                        key: ValueKey(_previewController),
                        controller: _previewController!,
                        fit: BoxFit.contain,
                      ),
                    // Before the first clip arrives the pane is the video's
                    // black fill; say what to do instead.
                    if (_previewController != null &&
                        _previewPath == null &&
                        !_previewBusy &&
                        _previewError == null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _emptyState(
                          theme,
                          icon: Icons.play_circle_outline,
                          text: _l10n.top5PreviewHint,
                          dark: true,
                        ),
                      ),
                    if (_previewError != null)
                      ColoredBox(
                        color: Colors.black,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _emptyState(
                            theme,
                            icon: Icons.error_outline,
                            text: _previewError!,
                            dark: true,
                          ),
                        ),
                      )
                    else if (_previewBusy)
                      ColoredBox(
                        color: Colors.black54,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _previewLabel,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _commentList(theme)),
        ],
            ),
          ),
        ],
      ),
    );
  }

  /// The last failure, inside the dialog so the user can read it.
  Widget _errorStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(28),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.red.withAlpha(70)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.error_outline,
                size: 14, color: Colors.red.shade300),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SelectableText(
                _dialogError!,
                maxLines: 4,
                style: TextStyle(fontSize: 11, color: Colors.red.shade200),
              ),
            ),
          ),
          IconButton(
            tooltip: _l10n.commonClose,
            iconSize: 14,
            splashRadius: 14,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _dialogError = null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  /// Voice picker: system voices, then the imported packs.
  Widget _buildVoiceRow(ThemeData theme) {
    final hasAny = _voices.isNotEmpty || _packs.isNotEmpty;
    return Row(
      children: [
        const Icon(Icons.record_voice_over_outlined, size: 16),
        const SizedBox(width: 8),
        Text(_l10n.top5VoiceLabel, style: TextStyle(fontSize: 12)),
        const SizedBox(width: 12),
        if (!hasAny)
          Text(_l10n.top5NoVoices,
              style: TextStyle(fontSize: 12, color: Colors.white38))
        else
          SizedBox(
            width: 300,
            child: DropdownButton<String>(
              value: _voiceId,
              isDense: true,
              isExpanded: true,
              hint: Text(_l10n.top5VoiceHint, style: TextStyle(fontSize: 12)),
              items: [
                for (final voice in _voices)
                  DropdownMenuItem(
                    value: voice.id,
                    child: Text(voice.label,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                for (final pack in _packs)
                  DropdownMenuItem(
                    value: _packValue(pack),
                    child: Text(_l10n.top5VoicePack(pack.label),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _voiceId = value),
            ),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _createVoicePack,
          icon: const Icon(Icons.mic_none, size: 16),
          label: Text(_l10n.top5CreatePack, style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: _importVoicePack,
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: Text(_l10n.top5Import, style: TextStyle(fontSize: 12)),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () =>
              openVoicePackGuideDialog(context, onRefresh: _loadVoices),
          icon: const Icon(Icons.help_outline, size: 14),
          label: Text(_l10n.top5VoiceGuide),
        ),
      ],
    );
  }

  Widget _commentList(ThemeData theme) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _picked.length,
      itemBuilder: (context, index) {
        final candidate = _picked[index];
        final take = _takeFor(candidate);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withAlpha(10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _rankBadge(index + 1),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(candidate.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  _tinyIconButton(
                    tooltip: _l10n.top5PreviewClip,
                    icon: Icons.play_arrow,
                    onPressed: () => _preview(candidate),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _comments[candidate.id],
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _l10n.top5CommentHint,
                  hintStyle:
                      const TextStyle(fontSize: 11, color: Colors.white38),
                  filled: true,
                  fillColor: _ink,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _tinyIconButton(
                    tooltip: _l10n.top5Audition,
                    icon: _voiceBusy
                        ? Icons.hourglass_empty
                        : Icons.volume_up_outlined,
                    onPressed: () => _previewVoice(candidate),
                  ),
                  // Replay, not re-clone: the take the user liked is on disk, so
                  // listening to it again is free.
                  _tinyIconButton(
                    tooltip: _l10n.top5PlayTake,
                    icon: Icons.play_circle_outline,
                    onPressed: take == null ? null : () => _playTake(take),
                  ),
                  // The seed is the take's identity: type it into the studio and
                  // the same delivery comes back.
                  if (take?.seed != null) ...[
                    const SizedBox(width: 2),
                    Tooltip(
                      message: _l10n.top5SeedHint,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _l10n.top5TakeSeed(take!.seed!),
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white54,
                              fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _narrationState(candidate, take),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Hand the finished reel to the OS default player.
  Future<void> _openOutput() async {
    final path = _outputPath;
    if (path == null) return;
    try {
      await Process.start('cmd', ['/c', 'start', '', path], runInShell: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_l10n.top5OpenFailed(e)),
        backgroundColor: Colors.red.shade700,
      ));
    }
  }

  // ---------------------------------------------------------------- footer
  Widget _footer(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          if (_busy) ...[
            SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, value: _progress),
            ),
            const SizedBox(width: 8),
            Text('$_busyLabel ${(_progress * 100).round()}%',
                style: theme.textTheme.bodySmall),
          ] else
            Text(
              _step == 0
                  ? _l10n.top5FooterPick(_picked.length, _wantedCount)
                  : _outputPath != null
                      ? _l10n.top5FooterDone
                      : _l10n.top5FooterNarrate,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const Spacer(),
          if (_step == 0) ...[
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: Text(_l10n.commonCancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _picked.length == _wantedCount && !_busy
                  ? () => setState(() => _step = 1)
                  : null,
              child: Text(_l10n.top5Next),
            ),
          ] else if (_outputPath != null) ...[
            FilledButton.icon(
              onPressed: _openOutput,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(_l10n.top5Watch),
            ),
            const SizedBox(width: 8),
            // A reel is a render, not a one-shot: change the voice or a
            // comment and make it again without closing the dialog.
            OutlinedButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.movie_creation_outlined, size: 16),
              label: Text(_l10n.top5Regenerate),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_l10n.commonClose),
            ),
          ] else ...[
            TextButton(
              onPressed: _busy ? null : () => setState(() => _step = 0),
              child: Text(_l10n.top5Back),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.movie_creation_outlined, size: 16),
              label: Text(_l10n.top5Generate(_wantedCount, _kindLabel)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- pieces
  Widget _panel(
    ThemeData theme, {
    required String title,
    required String trailing,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(trailing,
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(10)),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _emptyState(
    ThemeData theme, {
    required IconData icon,
    required String text,
    bool dark = false,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Colors.white24),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: dark ? Colors.white38 : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
