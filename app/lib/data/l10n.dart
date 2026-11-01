import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/settings_service.dart';

/// Typed localization strings for the app UI.
class AppStrings {
  // ── Toolbar ──
  final String openVideoFile;
  final String projectMenu;
  final String saveProject;
  final String loadProject;
  final String closeProject;
  final String noProject;
  final String settings;

  // ── Dialogs ──
  final String newProjectTitle;
  final String projectNameHint;
  final String cancel;
  final String cancelBtn;
  final String create;
  final String save;
  final String ok;
  final String okBtn;
  final String close;
  final String editDescription;
  final String delete;
  final String unsavedChanges;
  final String unsavedChangesMessage;
  final String discard;

  // ── Microsoft Store update prompt ──
  final String updateAvailableTitle;
  final String updateAvailableMessage;
  final String updateNow;
  final String updateLater;

  // ── Timeslot table ──
  final String timeslots;
  final String colNumber;
  final String colDescription;
  final String colFilename;
  final String colTime;
  final String colElapse;
  final String colRemote;
  final String colRemoteShort;
  final String colRating;
  final String colColor;
  final String noTimeslotsYet;
  final String useMarkButton;
  final String slotPrefix;
  final String editAction;
  final String deleteAction;
  final String remoteTooltip;
  final String localTooltip;

  // ── Control panel ──
  final String seekBack;
  final String playPause;
  final String seekForward;
  final String stop;
  final String mark;
  final String markTooltip;
  final String speed;
  final String make;
  final String makingHighlight;
  final String doneOutput;
  final String makeFailed;
  final String markTimeslot;
  final String descriptionHint;
  final String remote;
  final String timeslotMarked;
  final String failedToMark;

  // ── Template panel ──
  final String startupTemplate;
  final String transitionTemplate;
  final String endingTemplate;
  final String backgroundMusic;
  final String addTemplate;
  final String noTemplates;
  final String preview;
  final String bgMusicFile;
  final String missingTemplateFiles;
  final String templateFileNotFound;
  final String deleteTemplateTitle;
  final String deleteTemplateConfirm;
  final String editTitle;

  // ── Source file list ──
  final String sourceFiles;
  final String addVideoFiles;
  final String addVideoFilesShort;
  final String failedToAddFiles;
  final String noVideoFiles;
  final String clickToAdd;
  final String removeFromList;

  // ── Status bar ──
  final String projectPrefix;
  final String sourceFilesSuffix;
  final String timeslotsSuffix;
  final String videoInfoPlaceholder;
  final String appVersion;

  // ── Player ──
  final String noVideoLoaded;
  final String openVideo;
  final String unknownError;
  final String dismiss;

  // ── Settings ──
  final String settingsTitle;
  final String languageSection;
  final String languageLabel;
  final String aboutSection;
  final String appName;
  final String appVersionInfo;
  final String selectLanguage;

  // ── Project I/O ──
  final String noProjectToSave;
  final String saveFailed;
  final String loadFailed;
  final String projectSaved;
  final String projectLoaded;
  final String projectClosed;
  final String projectCleared;
  final String hlcprojFilter;

  // ── Zoom-in dialog ──
  final String zoomInPointTitle;
  final String zoomApplyToAll;
  final String zoomNext;
  final String zoomDone;
  final String zoomTimeslotOf;
  final String zoomFailedLoadFrame;

  // ── Render dialog ──
  final String renderDialogTitle;
  final String renderDialogMessage;

  // ── Resolution dialog ──
  final String outputResolution;
  final String resolutionNotAvailable;

  // ── Result folder ──
  final String resultFolder;

  // ── Preview dialog ──
  final String previewDialogTitle;
  final String previewStartupSection;
  final String previewTransitionSection;
  final String previewEndingSection;
  final String previewNoEnding;
  final String previewConfirm;
  final String previewTimeslotCount;
  final String previewTotalElapse;

  // ── Auto gen ──
  final String autoGen;
  final String autoGenTooltip;
  final String autoGenNeedSource;
  final String autoGenComingSoon;

  // ── Tracker bar ──
  final String timeline;

  // ── Translate ──
  final String translate;
  final String translating;
  final String translateDone;
  final String translateFailed;

  // ── Beginner guide ──
  final String guideTitle;
  final String guidePrev;
  final String guideNext;
  final String guideDone;
  final String guideDontShowAgain;
  final String helpSection;
  final String guideStep1;
  final String guideStep2;
  final String guideStep3;
  final String guideStep4;
  final String guideStep5;
  final String guideStep6;
  final String guideStep7;
  final String guideStep8;

  // ── "I want to" dropdown ──
  final String wantToMenu;
  final String wantMake;
  final String wantGoTo;

  // ── Go-to dialog ──
  final String gotoTitle;
  final String gotoDestTime;
  final String gotoBaseTime;
  final String gotoGo;
  final String gotoBadTime;
  final String gotoNoSource;
  final String gotoSeeked;
  final String gotoClamped;

  // ── Hotkeys ──
  final String hotkeySection;
  final String hotkeyTitle;
  final String hotkeyNameMark;
  final String hotkeyNameSeekBack;
  final String hotkeyNameSeekForward;
  final String hotkeyNamePlayPause;
  final String hotkeyNameGoTo;
  final String hotkeyNameSave;
  final String hotkeyNameNew;
  final String hotkeyNameOpen;
  final String hotkeyNameClose;
  final String hotkeyNameAddSource;
  final String hotkeyNameTemplates;

  // ── Error ──
  final String failedToOpenVideo;

  // ── Top 5 / cache / voice packs ──
  /// 'en' or 'zh'; the parameterised helpers below branch on it.
  final String code;
  final String menuTop5;
  final String menuCache;
  final String menuClipBreakdown;
  final String commonCancel;
  final String commonRefresh;
  final String commonClose;
  final String commonGotIt;
  final String voiceGuideTitle;
  final String voiceGuideIntro;
  final String voiceGuideStep1;
  final String voiceGuideStep2;
  final String voiceGuideAfter;
  final String voiceGuideOwnTitle;
  final String voiceGuideOwnBody;
  final String voiceGuideOwnImport;
  final String voiceGuideEngine;
  final String voiceGuideNarrator;
  final String voiceGuideLanguage;
  final String cacheTitle;
  final String cacheSlicesName;
  final String cacheSlicesWhat;
  final String cacheNarrationName;
  final String cacheNarrationWhat;
  final String cacheWorkName;
  final String cacheWorkWhat;
  final String cacheTemplatesName;
  final String cacheTemplatesWhat;
  final String cacheMakeName;
  final String cacheMakeWhat;
  final String cacheEmpty;
  final String cacheOpen;
  final String cacheClear;
  final String cacheClearing;
  final String cacheConfirmNote;
  final String cacheConfirmOk;
  final String cacheNoPermission;

  /// '{count} files / {size}', '{name}' placeholders filled by [fill].
  final String cacheCountSize;
  final String top5Title;
  final String top5StepSelect;
  final String top5StepPreview;
  final String top5LevelWeek;
  final String top5LevelMonth;
  final String top5LevelYear;
  final String top5KindGoal;
  final String top5KindSave;
  final String top5ThisWeek;
  final String top5ThisMonth;
  final String top5ThisYear;
  final String top5PoolTitle;
  final String top5PoolEmptyWeek;
  final String top5PoolEmptyMonth;
  final String top5PoolEmptyYear;
  final String top5RanksTitle;
  final String top5RanksHint;
  final String top5MoveUp;
  final String top5MoveDown;
  final String top5Remove;
  final String top5PreviewHint;
  final String top5VoiceLabel;
  final String top5NoVoices;
  final String top5VoiceHint;
  final String top5CreatePack;
  final String top5Import;
  final String top5VoiceGuide;
  final String top5PreviewClip;
  final String top5CommentHint;
  final String top5Audition;
  final String top5PlayTake;
  final String top5TakeMissing;
  final String top5SeedHint;
  final String top5PreviewNoPicture;
  final String top5ReloadingPlayer;
  final String top5Seed;
  final String top5SeedInvalid;
  final String top5SeedRange;
  final String top5FooterDone;
  final String top5FooterNarrate;
  final String top5Next;
  final String top5Watch;
  final String top5Regenerate;
  final String top5Back;
  final String top5NoComment;
  final String top5NeedComment;
  final String top5NeedVoice;
  final String top5CloneFailed;
  final String top5PreparingClip;
  final String top5ClipNoPreview;
  final String top5LoadingPlayer;
  final String top5NeedBgm;
  final String top5BusyPrepare;
  final String top5NextTime;
  final String top5CoverTitle;
  final String top5ClipNoVideo;
  final String top5SliceUnplayable;
  final String top5SliceFailedShort;
  final String top5VoiceRefreshed;
  final String top5ImportTitle;
  final String top5ImportFolder;
  final String top5ImportAudio;
  final String top5PickPackFolder;
  final String top5FolderNoAudio;
  final String top5FolderOneAudio;
  final String top5ImportFailedShort;
  final String top5StudioMissing;
  final String top5EngineMissing;
  final String top5EngineNotInstalled;
  final String top5EngineMissingHint;

  // ── Phone marking ──
  final String menuPhoneMarking;
  final String phoneMarkingTitle;
  final String phoneMarkingScan;
  final String phoneMarkingAddress;
  final String phoneMarkingToken;
  final String phoneMarkingOpen;
  final String phoneMarkingStop;
  final String phoneMarkingRunning;
  final String phoneMarkingStopped;
  final String phoneMarkingNoSources;
  final String phoneMarkingLocalhostHint;
  final String phoneMarkingStartFailed;
  final String phoneMarkingFirewallHint;
  final String phoneMarkingPageTitle;
  final String phoneMarkingPageSources;
  final String phoneMarkingPagePlayer;
  final String phoneMarkingPagePreparing;
  final String phoneMarkingPageFailed;

  // ── AI marking (docs/ai_marking.md) ──
  final String menuAiMarking;
  final String aiTitle;
  final String aiApiKey;
  final String aiRememberKey;
  final String aiShowKey;
  final String aiHideKey;
  final String aiModel;
  final String aiPickVideo;
  final String aiNoFile;
  final String aiSupportedFormats;
  final String aiUnsupportedFormat;
  final String aiStart;
  final String aiReanalyze;
  final String aiStageAudio;
  final String aiStageMotion;
  final String aiStageDetect;
  final String aiStageJudge;
  final String aiStageDone;
  final String aiResultsTitle;
  final String aiVerdictHighlight;
  final String aiVerdictOrdinary;
  final String aiVerdictUnjudged;
  final String aiView;
  final String aiSaveProject;
  final String aiUnsupportedBanner;
  final String aiInvalidKey;
  final String aiNoHighlight;
  final String aiNeedKey;
  final String aiNeedFile;
  final String aiNoFfmpeg;
  final String aiMotionUnavailable;
  final String aiCancelled;
  final String aiSavedTo;

  // ── AI 打点 · 批量与高光列表 (docs/ai_marking.md §批量) ──
  final String aiNoFileHighlights;
  final String aiFileSkipped;

  // ── 球门标定 (docs/ai_marking.md §球门标定) ──
  final String aiCalibrateGoal;
  final String goalCalibTitle;
  final String goalCalibHint;
  final String goalCalibEmpty;
  final String goalCalibClear;
  final String goalCalibSave;
  final String goalCalibApplySiblings;
  final String goalCalibNoFrame;
  final String goalCalibSaveFailed;
  final String goalCalibLoading;

  bool get _zh => code == 'zh';

  /// "Picked 3/5" pill in step 1.
  String top5Picked(int picked, int want) =>
      _zh ? '已选 $picked / $want' : 'Picked $picked / $want';

  /// "12 clips" in the pool header.
  String top5PoolCount(int count) => _zh ? '$count 个' : '$count clips';

  /// "Voice pack · My voice · 7.0 s" in the dropdown.
  String top5VoicePack(String label) =>
      _zh ? '语音包 · $label' : 'Voice pack · $label';

  /// "Top 5 goals" / "5佳进球".
  String top5ReelTitle(int want, String kind) =>
      _zh ? '$want佳$kind' : 'Top $want $kind';

  /// "Generate Top 5 goals".
  String top5Generate(int want, String kind) =>
      _zh ? '生成 $want佳$kind' : 'Generate Top $want $kind';

  /// Footer hint in step 1.
  String top5FooterPick(int picked, int want) => _zh
      ? '已选 $picked/$want \u00b7 点击左侧片段按名次加入,NO.1 为最佳'
      : 'Picked $picked/$want \u00b7 click a clip on the left to add it by rank, No. 1 is best';

  /// Step 1 pill: the reel already rendered for this period was filled in.
  String top5RestoredCache(String period, int count) => _zh
      ? '已恢复 $period 的成片($count 条)'
      : 'Restored the $period reel ($count picks)';

  /// Intro card badge: "TOP 5 · Top 5 goals · 2026-W43".
  String top5IntroBadge(int want, String title, String period) =>
      'TOP $want · $title · $period';

  String top5IntroWeek(int year, String week, String title) => _zh
      ? '$year 年第 $week 周 · $title'
      : 'Week $week of $year · $title';

  String top5IntroMonth(int year, int month, String title) =>
      _zh ? '$year 年 $month 月 · $title' : '$year-$month · $title';

  String top5IntroYear(int year, String title) =>
      _zh ? '$year 年度 · $title' : '$year · $title';

  /// "Narration: My voice (cloned locally)".
  String top5NarrationPack(String name) =>
      _zh ? '解说:$name(本地克隆)' : 'Narration: $name (cloned locally)';

  /// The same line after an audition: the render reuses the take just heard.
  String top5NarrationPackCached(String name) => _zh
      ? '解说:$name(本地克隆 · 用已试听版本)'
      : 'Narration: $name (local clone, last audition kept)';

  /// "Narration: system voice (Huihui)".
  String top5NarrationSystem(String name) => _zh
      ? '解说:系统语音${name.isEmpty ? '' : '($name)'}'
      : 'Narration: system voice${name.isEmpty ? '' : ' ($name)'}';

  String top5ClipFallback(int position) =>
      _zh ? '片段 $position' : 'Clip $position';

  /// Clip subtitle: "123.4s in · 8.0s".
  String top5ClipWindow(String start, String duration) =>
      _zh ? '$start 起 · $duration' : 'from ${start}s · $duration';

  String top5BusyClone(int index, int total) =>
      _zh ? '克隆解说 $index/$total' : 'Cloning narration $index/$total';

  /// Rendering with the take that was auditioned, no clone needed.
  String top5BusyTake(int index, int total) =>
      _zh ? '使用试听解说 $index/$total' : 'Using auditioned narration $index/$total';

  /// The seed badge next to the take's play button: "seed 123456789".
  String top5TakeSeed(int seed) => 'seed $seed';

  String top5BusySynth(int index, int total) =>
      _zh ? '合成解说 $index/$total' : 'Synthesising narration $index/$total';

  String top5BusyClip(int rank, int total) =>
      _zh ? '准备片段 $rank/$total' : 'Preparing clip $rank/$total';

  String top5BusyRender(String title) =>
      _zh ? '渲染 $title' : 'Rendering $title';

  /// Tooltip: which project date the period came from.
  String top5ProjectDateHint(String iso) => _zh
      ? '周期按项目日期 $iso 计算'
      : 'Period derives from the project date $iso';

  String top5PackReferenceMissing(String name) => _zh
      ? '语音包「$name」的参考录音不见了,请重新导入'
      : 'The reference recording of “$name” is gone, import it again';

  String top5Imported(String name) =>
      _zh ? '已导入「$name」' : 'Imported “$name”';

  String top5StudioLaunchFailed(int code, String detail) => _zh
      ? '语音工作室没有启动(退出码 $code)$detail'
      : 'Voice Studio did not start (exit code $code)$detail';

  String top5StudioStartError(Object error) => _zh
      ? '启动语音工作室失败:$error'
      : 'Could not start Voice Studio: $error';

  String top5ImportFailed(Object error) => _zh
      ? '导入语音包失败:$error'
      : 'Importing the voice pack failed: $error';

  String top5AudioConvertFailed(String reason) => _zh
      ? '音频转换失败:$reason'
      : 'Converting the audio failed: $reason';

  String top5SliceFailed(int code) =>
      _zh ? '切片失败(退出码 $code)' : 'Slicing failed (exit code $code)';

  String top5PreviewFailed(Object reason) =>
      _zh ? '预览失败:$reason' : 'Preview failed: $reason';

  String top5BgmMissing(String path) => _zh
      ? '背景音乐文件不存在: $path'
      : 'The background music file is missing: $path';

  String top5ClipSliceFailed(String title) => _zh
      ? '片段切片失败: $title'
      : 'Could not cut $title';

  String top5SavedTo(String path) => _zh ? '已生成 $path' : 'Rendered $path';

  String top5GenerateFailed(Object error) =>
      _zh ? '生成失败: $error' : 'Rendering failed: $error';

  String top5OpenFailed(Object error) =>
      _zh ? '打开失败: $error' : 'Could not open it: $error';

  /// Fill `{name}` placeholders.
  String fill(String template, Map<String, Object?> values) {
    var out = template;
    for (final entry in values.entries) {
      out = out.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return out;
  }



  String cacheCount(int count, String size) =>
      _zh ? '$count 个 / $size' : '$count files / $size';

  String cacheConfirmTitle(String name) =>
      _zh ? '清空「$name」?' : 'Clear \u201c$name\u201d?';

  String cacheConfirmTotal(int count, String size) => _zh
      ? '共 $count 个文件 / $size。'
      : '$count files / $size.';

  String cacheAlreadyEmpty(String name) =>
      _zh ? '「$name」本来就是空的' : '\u201c$name\u201d is already empty';

  String cachePartial(String name, int removed, int total) => _zh
      ? '「$name」只清掉了 $removed/$total 个文件，'
      : 'Only $removed of $total files in \u201c$name\u201d were cleared, ';

  String cacheClearFailed(String name, Object error) =>
      _zh ? '清空「$name」失败:$error' : 'Clearing \u201c$name\u201d failed: $error';

  String explorerFailed(Object error) =>
      _zh ? 'explorer 启动失败: $error' : 'Could not open Explorer: $error';

  /// 「AI 打点」: how many of the candidates the model could not judge.
  String aiFailedCount(int count) => _zh
      ? '$count 段判定失败(已跳过)'
      : '$count clips failed to judge (skipped)';

  /// 「AI 打点」: "高光 3 / 12" in the results header.
  String aiHighlightCount(int passed, int total) =>
      _zh ? '高光 $passed / $total' : '$passed highlights of $total';

  String aiAnalysisFailed(Object error) =>
      _zh ? '分析失败:$error' : 'Analysing failed: $error';

  String aiSaveFailed(Object error) =>
      _zh ? '保存项目失败:$error' : 'Saving the project failed: $error';

  /// Description for a candidate that never got a model sentence.
  String aiCandidateFallback(int index) =>
      _zh ? 'AI 候选 $index' : 'AI candidate $index';

  /// 「已选 11 个文件（共 125.6 分钟）」 — the picker summary; [minutes] is
  /// already formatted, and `—` when ffprobe could not read the lengths.
  String aiPickedFiles(int count, String minutes) => _zh
      ? '已选 $count 个文件（共 $minutes 分钟）'
      : '$count files selected ($minutes min)';

  /// File-level progress, above the bar: 「第 2/11 个文件 · 已完成候选 47 段」.
  ///
  /// [candidates] is what the batch has produced so far, this file included;
  /// the stage-level line (抽音频 / 逐段判定 …) stays under the bar.
  String aiBatchProgress(int index, int total, int candidates) => _zh
      ? '第 $index/$total 个文件 · 已完成候选 $candidates 段'
      : 'File $index/$total · $candidates candidates so far';

  /// The 「高光片段」 region title, total included: 「高光片段 · 共 12 段」.
  String aiHighlightsTotal(int count) =>
      _zh ? '高光片段 · 共 $count 段' : 'Highlights · $count clips';

  /// One file's group header trailing text: 「4 段高光」.
  String aiFileHighlightCount(int count) =>
      _zh ? '$count 段高光' : '$count highlights';

  /// One file's candidate group trailing text: 「47 段候选」.
  String aiFileCandidateCount(int count) =>
      _zh ? '$count 段候选' : '$count candidates';

  /// 「已将球门标定应用到 10 个文件」 — one calibration covered the batch.
  String aiCalibAppliedToBatch(int count) => _zh
      ? '已将球门标定应用到 $count 个文件'
      : 'Applied the goal calibration to $count files';

  /// 「1 个文件失败」 in the batch footer, next to the per-segment failures.
  String aiBatchFileFailed(int count) =>
      _zh ? '$count 个文件失败' : '$count file(s) failed';

  /// The model's `kind` as a UI label (`goal` / `save` / `shot` / `other`).
  String aiKindLabel(String kind) => switch (kind) {
        'goal' => _zh ? '进球' : 'Goal',
        'save' => _zh ? '扑救' : 'Save',
        'shot' => _zh ? '射门' : 'Shot',
        'other' => _zh ? '其他' : 'Other',
        _ => '—',
      };

  /// 球门标定: the confirmation after saving, `已标定 2 个球门`.
  String goalCalibSaved(int count) =>
      _zh ? '已标定 $count 个球门' : 'Calibrated $count goal(s)';

  /// 球门标定: overlay label and coordinate line prefix, 1-based.
  String goalCalibGoalLabel(int index) => _zh ? '球门 $index' : 'Goal $index';

  const AppStrings({
    required this.openVideoFile,
    required this.noProject,
    required this.settings,
    required this.newProjectTitle,
    required this.projectNameHint,
    required this.cancel,
    required this.cancelBtn,
    required this.create,
    required this.save,
    required this.ok,
    required this.okBtn,
    required this.close,
    required this.editDescription,
    required this.delete,
    required this.unsavedChanges,
    required this.unsavedChangesMessage,
    required this.discard,
    required this.updateAvailableTitle,
    required this.updateAvailableMessage,
    required this.updateNow,
    required this.updateLater,
    required this.projectMenu,
    required this.saveProject,
    required this.loadProject,
    required this.closeProject,
    required this.timeslots,
    required this.colNumber,
    required this.colDescription,
    required this.colFilename,
    required this.colTime,
    required this.colElapse,
    required this.colRemote,
    required this.colRemoteShort,
    required this.colRating,
    required this.colColor,
    required this.noTimeslotsYet,
    required this.useMarkButton,
    required this.slotPrefix,
    required this.editAction,
    required this.deleteAction,
    required this.remoteTooltip,
    required this.localTooltip,
    required this.seekBack,
    required this.playPause,
    required this.seekForward,
    required this.stop,
    required this.mark,
    required this.markTooltip,
    required this.speed,
    required this.make,
    required this.makingHighlight,
    required this.doneOutput,
    required this.makeFailed,
    required this.markTimeslot,
    required this.descriptionHint,
    required this.remote,
    required this.timeslotMarked,
    required this.failedToMark,
    required this.startupTemplate,
    required this.transitionTemplate,
    required this.endingTemplate,
    required this.backgroundMusic,
    required this.addTemplate,
    required this.noTemplates,
    required this.preview,
    required this.bgMusicFile,
    required this.missingTemplateFiles,
    required this.templateFileNotFound,
    required this.deleteTemplateTitle,
    required this.deleteTemplateConfirm,
    required this.editTitle,
    required this.sourceFiles,
    required this.addVideoFiles,
    required this.addVideoFilesShort,
    required this.failedToAddFiles,
    required this.noVideoFiles,
    required this.clickToAdd,
    required this.removeFromList,
    required this.projectPrefix,
    required this.sourceFilesSuffix,
    required this.timeslotsSuffix,
    required this.videoInfoPlaceholder,
    required this.appVersion,
    required this.noVideoLoaded,
    required this.openVideo,
    required this.unknownError,
    required this.dismiss,
    required this.settingsTitle,
    required this.languageSection,
    required this.languageLabel,
    required this.aboutSection,
    required this.appName,
    required this.appVersionInfo,
    required this.selectLanguage,
    required this.failedToOpenVideo,
    required this.noProjectToSave,
    required this.saveFailed,
    required this.loadFailed,
    required this.projectSaved,
    required this.projectLoaded,
    required this.projectClosed,
    required this.projectCleared,
    required this.hlcprojFilter,
    required this.zoomInPointTitle,
    required this.zoomApplyToAll,
    required this.zoomNext,
    required this.zoomDone,
    required this.zoomTimeslotOf,
    required this.zoomFailedLoadFrame,
    required this.renderDialogTitle,
    required this.renderDialogMessage,
    required this.outputResolution,
    required this.resolutionNotAvailable,
    required this.resultFolder,
    required this.previewDialogTitle,
    required this.previewStartupSection,
    required this.previewTransitionSection,
    required this.previewEndingSection,
    required this.previewNoEnding,
    required this.previewConfirm,
    required this.previewTimeslotCount,
    required this.previewTotalElapse,
    required this.autoGen,
    required this.autoGenTooltip,
    required this.autoGenNeedSource,
    required this.autoGenComingSoon,
    required this.timeline,
    required this.translate,
    required this.translating,
    required this.translateDone,
    required this.translateFailed,
    required this.guideTitle,
    required this.guidePrev,
    required this.guideNext,
    required this.guideDone,
    required this.guideDontShowAgain,
    required this.helpSection,
    required this.guideStep1,
    required this.guideStep2,
    required this.guideStep3,
    required this.guideStep4,
    required this.guideStep5,
    required this.guideStep6,
    required this.guideStep7,
    required this.guideStep8,
    required this.wantToMenu,
    required this.wantMake,
    required this.wantGoTo,
    required this.gotoTitle,
    required this.gotoDestTime,
    required this.gotoBaseTime,
    required this.gotoGo,
    required this.gotoBadTime,
    required this.gotoNoSource,
    required this.gotoSeeked,
    required this.gotoClamped,
    required this.hotkeySection,
    required this.hotkeyTitle,
    required this.hotkeyNameMark,
    required this.hotkeyNameSeekBack,
    required this.hotkeyNameSeekForward,
    required this.hotkeyNamePlayPause,
    required this.hotkeyNameGoTo,
    required this.hotkeyNameSave,
    required this.hotkeyNameNew,
    required this.hotkeyNameOpen,
    required this.hotkeyNameClose,
    required this.hotkeyNameAddSource,
    required this.hotkeyNameTemplates,
    required this.code,
    required this.menuTop5,
    required this.menuCache,
    required this.menuClipBreakdown,
    required this.commonCancel,
    required this.commonRefresh,
    required this.commonClose,
    required this.commonGotIt,
    required this.voiceGuideTitle,
    required this.voiceGuideIntro,
    required this.voiceGuideStep1,
    required this.voiceGuideStep2,
    required this.voiceGuideAfter,
    required this.voiceGuideOwnTitle,
    required this.voiceGuideOwnBody,
    required this.voiceGuideOwnImport,
    required this.voiceGuideEngine,
    required this.voiceGuideNarrator,
    required this.voiceGuideLanguage,
    required this.cacheTitle,
    required this.cacheSlicesName,
    required this.cacheSlicesWhat,
    required this.cacheNarrationName,
    required this.cacheNarrationWhat,
    required this.cacheWorkName,
    required this.cacheWorkWhat,
    required this.cacheTemplatesName,
    required this.cacheTemplatesWhat,
    required this.cacheMakeName,
    required this.cacheMakeWhat,
    required this.cacheEmpty,
    required this.cacheOpen,
    required this.cacheClear,
    required this.cacheClearing,
    required this.cacheConfirmNote,
    required this.cacheConfirmOk,
    required this.cacheNoPermission,
    required this.cacheCountSize,
    required this.top5Title,
    required this.top5StepSelect,
    required this.top5StepPreview,
    required this.top5LevelWeek,
    required this.top5LevelMonth,
    required this.top5LevelYear,
    required this.top5KindGoal,
    required this.top5KindSave,
    required this.top5ThisWeek,
    required this.top5ThisMonth,
    required this.top5ThisYear,
    required this.top5PoolTitle,
    required this.top5PoolEmptyWeek,
    required this.top5PoolEmptyMonth,
    required this.top5PoolEmptyYear,
    required this.top5RanksTitle,
    required this.top5RanksHint,
    required this.top5MoveUp,
    required this.top5MoveDown,
    required this.top5Remove,
    required this.top5PreviewHint,
    required this.top5VoiceLabel,
    required this.top5NoVoices,
    required this.top5VoiceHint,
    required this.top5CreatePack,
    required this.top5Import,
    required this.top5VoiceGuide,
    required this.top5PreviewClip,
    required this.top5CommentHint,
    required this.top5Audition,
    required this.top5PlayTake,
    required this.top5TakeMissing,
    required this.top5SeedHint,
    required this.top5PreviewNoPicture,
    required this.top5ReloadingPlayer,
    required this.top5Seed,
    required this.top5SeedInvalid,
    required this.top5SeedRange,
    required this.top5FooterDone,
    required this.top5FooterNarrate,
    required this.top5Next,
    required this.top5Watch,
    required this.top5Regenerate,
    required this.top5Back,
    required this.top5NoComment,
    required this.top5NeedComment,
    required this.top5NeedVoice,
    required this.top5CloneFailed,
    required this.top5PreparingClip,
    required this.top5ClipNoPreview,
    required this.top5LoadingPlayer,
    required this.top5NeedBgm,
    required this.top5BusyPrepare,
    required this.top5NextTime,
    required this.top5CoverTitle,
    required this.top5ClipNoVideo,
    required this.top5SliceUnplayable,
    required this.top5SliceFailedShort,
    required this.top5VoiceRefreshed,
    required this.top5ImportTitle,
    required this.top5ImportFolder,
    required this.top5ImportAudio,
    required this.top5PickPackFolder,
    required this.top5FolderNoAudio,
    required this.top5FolderOneAudio,
    required this.top5ImportFailedShort,
    required this.top5StudioMissing,
    required this.top5EngineMissing,
    required this.top5EngineNotInstalled,
    required this.top5EngineMissingHint,
    required this.menuPhoneMarking,
    required this.phoneMarkingTitle,
    required this.phoneMarkingScan,
    required this.phoneMarkingAddress,
    required this.phoneMarkingToken,
    required this.phoneMarkingOpen,
    required this.phoneMarkingStop,
    required this.phoneMarkingRunning,
    required this.phoneMarkingStopped,
    required this.phoneMarkingNoSources,
    required this.phoneMarkingLocalhostHint,
    required this.phoneMarkingStartFailed,
    required this.phoneMarkingFirewallHint,
    required this.phoneMarkingPageTitle,
    required this.phoneMarkingPageSources,
    required this.phoneMarkingPagePlayer,
    required this.phoneMarkingPagePreparing,
    required this.phoneMarkingPageFailed,
    required this.menuAiMarking,
    required this.aiTitle,
    required this.aiApiKey,
    required this.aiRememberKey,
    required this.aiShowKey,
    required this.aiHideKey,
    required this.aiModel,
    required this.aiPickVideo,
    required this.aiNoFile,
    required this.aiSupportedFormats,
    required this.aiUnsupportedFormat,
    required this.aiStart,
    required this.aiReanalyze,
    required this.aiStageAudio,
    required this.aiStageMotion,
    required this.aiStageDetect,
    required this.aiStageJudge,
    required this.aiStageDone,
    required this.aiResultsTitle,
    required this.aiVerdictHighlight,
    required this.aiVerdictOrdinary,
    required this.aiVerdictUnjudged,
    required this.aiView,
    required this.aiSaveProject,
    required this.aiUnsupportedBanner,
    required this.aiInvalidKey,
    required this.aiNoHighlight,
    required this.aiNeedKey,
    required this.aiNeedFile,
    required this.aiNoFfmpeg,
    required this.aiMotionUnavailable,
    required this.aiCancelled,
    required this.aiSavedTo,
    required this.aiNoFileHighlights,
    required this.aiFileSkipped,
    required this.aiCalibrateGoal,
    required this.goalCalibTitle,
    required this.goalCalibHint,
    required this.goalCalibEmpty,
    required this.goalCalibClear,
    required this.goalCalibSave,
    required this.goalCalibApplySiblings,
    required this.goalCalibNoFrame,
    required this.goalCalibSaveFailed,
    required this.goalCalibLoading,
  });
}

const _en = AppStrings(
  openVideoFile: 'Open Video File',
  noProject: 'No project',
  settings: 'Settings',
  newProjectTitle: 'New Project',
  projectNameHint: 'Project name',
  cancel: 'Cancel',
  cancelBtn: 'Cancel',
  create: 'Create',
  save: 'Save',
  ok: 'OK',
  okBtn: 'OK',
  close: 'Close',
  editDescription: 'Edit Description',
  delete: 'Delete',
  unsavedChanges: 'Unsaved Changes',
  unsavedChangesMessage:
      'You have unsaved changes. Would you like to save before continuing?',
  discard: 'Discard',
  updateAvailableTitle: 'Update Available',
  updateAvailableMessage:
      'A newer version of Highlight Creator is available in the Microsoft Store.',
  updateNow: 'Update Now',
  updateLater: 'Later',
  projectMenu: 'Project',
  saveProject: 'Save Project',
  loadProject: 'Load Project',
  closeProject: 'Close Project',
  timeslots: 'Timeslots',
  colNumber: '#',
  colDescription: 'Description',
  colFilename: 'Filename',
  colTime: 'Time',
  colElapse: 'Elapse',
  colRemote: 'Remote',
  colRemoteShort: 'Remote',
  colRating: '★',
  colColor: 'Color',
  noTimeslotsYet: 'No timeslots yet.',
  useMarkButton: 'Use the Mark button to add.',
  slotPrefix: 'Slot ',
  editAction: 'Edit',
  deleteAction: 'Delete',
  remoteTooltip: 'Remote (zoom-in)',
  localTooltip: 'Local',
  seekBack: 'Seek -5s (←)',
  playPause: 'Play/Pause (Space)',
  seekForward: 'Seek +5s (→)',
  stop: 'Stop (Esc)',
  mark: 'Mark (Ctrl+M)',
  markTooltip: 'Mark a highlight timeslot',
  speed: 'Speed',
  make: 'Make',
  makingHighlight: 'Making highlight reel...',
  doneOutput: 'Done! Output: ',
  makeFailed: 'Make failed: ',
  markTimeslot: 'Mark Timeslot',
  descriptionHint: 'Description',
  remote: 'Remote',
  timeslotMarked: 'Timeslot marked',
  failedToMark: 'Failed to mark: ',
  startupTemplate: 'Startup Template',
  transitionTemplate: 'Transition Template',
  endingTemplate: 'Ending Template',
  backgroundMusic: 'Background Music',
  addTemplate: 'Add template',
  noTemplates: 'No templates configured.',
  preview: 'Preview',
  bgMusicFile: 'Background music file: ',
  missingTemplateFiles: 'Missing Template Files',
  templateFileNotFound: 'Template file not found:',
  deleteTemplateTitle: 'Delete Template',
  deleteTemplateConfirm: 'Delete {name}?',
  editTitle: 'Edit title',
  sourceFiles: 'Source Files',
  addVideoFiles: 'Add Video Files',
  addVideoFilesShort: 'Add video file',
  failedToAddFiles: 'Failed to add files: ',
  noVideoFiles: 'No video files',
  clickToAdd: 'Click + to add',
  removeFromList: 'Remove from list',
  projectPrefix: 'Project: ',
  sourceFilesSuffix: ' source files',
  timeslotsSuffix: ' timeslots',
  videoInfoPlaceholder: '1920×1080 · H.264 · 30fps',
  appVersion: 'Highlight Creator v0.4.1.0',
  noVideoLoaded: 'No video loaded',
  openVideo: 'Open Video',
  unknownError: 'Unknown error',
  dismiss: 'Dismiss',
  settingsTitle: 'Settings',
  languageSection: 'Language',
  languageLabel: 'Language',
  aboutSection: 'About',
  appName: 'Highlight Creator',
  appVersionInfo: 'Version 0.4.1.0',
  selectLanguage: 'Select Language',
  failedToOpenVideo: 'Failed to open video: ',
  projectSaved: 'Project saved.',
  projectLoaded: 'Project loaded.',
  projectClosed: 'Project closed.',
  projectCleared: 'Project cleared.',
  hlcprojFilter: 'Highlight Creator Project',
  noProjectToSave: 'No project to save.',
  saveFailed: 'Save failed: ',
  loadFailed: 'Load failed: ',
  zoomInPointTitle: 'Zoom in point configuration',
  zoomApplyToAll: 'Apply to all',
  zoomNext: 'Next',
  zoomDone: 'Done',
  zoomTimeslotOf: 'Timeslot',
  zoomFailedLoadFrame: 'Failed to load frame',
  renderDialogTitle: 'Rendering\u2026',
  renderDialogMessage: 'Please wait while creating highlight video',
  outputResolution: 'Output Resolution',
  resolutionNotAvailable: 'Not available (higher than source)',
  resultFolder: 'Result Folder',
  previewDialogTitle: 'Preview & Confirm',
  previewStartupSection: 'Startup',
  previewTransitionSection: 'Transition',
  previewEndingSection: 'Ending',
  previewNoEnding: 'No ending configured',
  previewConfirm: 'Confirm & Make',
  previewTimeslotCount: 'timeslots',
  previewTotalElapse: 'Total elapse: ',
  autoGen: 'Auto Gen',
  autoGenTooltip:
      'It will assist you to generate highlight semi-auto. It might be very slow if the hardware is not good enough. Rely on local algrithm. Safe and free.',
  autoGenNeedSource: 'Please add video source files first.',
  autoGenComingSoon: 'Auto-generate is coming soon.',
  timeline: 'Timeline',
  translate: 'Translate',
  translating: 'Transcribing audio...',
  translateDone: 'Transcription saved: ',
  translateFailed: 'Transcription failed: ',
  wantToMenu: 'I want to',
  wantMake: 'Make',
  wantGoTo: 'Go to',
  gotoTitle: 'Go to time',
  gotoDestTime: 'Destination time (hh:mm:ss)',
  gotoBaseTime: 'Base time (optional, hh:mm:ss)',
  gotoGo: 'Go',
  gotoBadTime: 'Invalid time format \u2014 use hh:mm:ss',
  gotoNoSource: 'No source videos in the project',
  gotoSeeked: 'Jumped to ',
  gotoClamped: ' (beyond the total duration, clamped to the end)',
  hotkeySection: 'Hotkeys',
  hotkeyTitle: 'Keyboard Shortcuts',
  hotkeyNameMark: 'Mark',
  hotkeyNameSeekBack: 'Seek back 5s',
  hotkeyNameSeekForward: 'Seek forward 5s',
  hotkeyNamePlayPause: 'Play / Pause',
  hotkeyNameGoTo: 'Go to dialog',
  hotkeyNameSave: 'Save project',
  hotkeyNameNew: 'New project',
  hotkeyNameOpen: 'Open project',
  hotkeyNameClose: 'Close project',
  hotkeyNameAddSource: 'Add video sources',
  hotkeyNameTemplates: 'Template config',
  guideTitle: 'Beginner Guide',
  guidePrev: 'Previous',
  guideNext: 'Next',
  guideDone: 'Done',
  guideDontShowAgain: 'Don\u2019t show again on startup',
  helpSection: 'Help',
  guideStep1: 'In Source Files, click the add button to add video files',
  guideStep2: 'During playback, click Mark to record the highlight moment',
  guideStep3:
      'Add a text description for the transition; check the zoom-in box if you want to zoom in on the remote picture',
  guideStep4: 'Add a custom startup or use the built-in one',
  guideStep5: 'Add a custom transition or use the built-in one',
  guideStep6: 'Add a custom ending or use the built-in one',
  guideStep7: 'Add custom background music or use the built-in one',
  guideStep8:
      'Use \u201cI want to\u201d \u2192 Make, choose the output resolution, and wait for the final video',
  code: 'en',
  menuTop5: 'Top 5 / Top 10',
  menuCache: 'Cache files',
  menuClipBreakdown: 'Clip breakdown',
  commonCancel: 'Cancel',
  commonRefresh: 'Refresh',
  commonClose: 'Close',
  commonGotIt: 'Got it',
  voiceGuideTitle: 'Windows voice pack guide',
  voiceGuideIntro:
      'Narration is synthesised on this machine: no network, no API key. The Chinese voices Windows ships with sound robotic, so download a natural voice by either route below.',
  voiceGuideStep1:
      'Settings \u2192 Accessibility \u2192 Narrator \u2192 Add voices \u2192 download a Chinese (Simplified) natural voice (Xiaoxiao / Xiaoyi / Yunxi \u2026)',
  voiceGuideStep2:
      'Settings \u2192 Time & language \u2192 Language & region \u2192 Chinese (Simplified) \u2192 Language options \u2192 Speech \u2192 download a voice pack',
  voiceGuideAfter:
      'Back in the app, press Refresh to see the new voice. If the list does not change, restart the app once.',
  voiceGuideOwnTitle: 'Use my own voice',
  voiceGuideOwnBody:
      'Create voice pack opens the Voice Studio, a separate recording app. Read the prompt, audition the result, save it, and the pack then appears under Narration voice.',
  voiceGuideOwnImport:
      'Or press Import to load a .voicepack folder someone gave you, or a single recording.',
  voiceGuideEngine:
      'Cloning needs a local engine (Python + GPU), which is not bundled: run tools\\voice_clone\\setup.bat once. Everything stays offline afterwards and audio never leaves this machine.',
  voiceGuideNarrator: 'Open Narrator voice settings',
  voiceGuideLanguage: 'Open language voice settings',
  cacheTitle: 'Cache files',
  cacheSlicesName: 'Top-5 clip cache',
  cacheSlicesWhat:
      'One clean slice per time slot, shared by preview and generate; clearing it just means the next cut is a little slower.',
  cacheNarrationName: 'Top-5 narration',
  cacheNarrationWhat:
      'Audio from TTS, cloning and auditions, including the last audition of each line; safe to clear after a render.',
  cacheWorkName: 'Top-5 render scratch',
  cacheWorkWhat:
      'Rank cards, transitions, clips and the concat master; useless once the reel exists.',
  cacheTemplatesName: 'Built-in template videos',
  cacheTemplatesWhat:
      'Transitions, startups and endings, rendered on first use; clearing costs a few minutes to rebuild.',
  cacheMakeName: 'Make render leftovers',
  cacheMakeWhat:
      'Remade on every Make run. Clearing them means Top-5 cuts from the source video instead of reusing them (slower).',
  cacheEmpty: 'empty',
  cacheOpen: 'Open',
  cacheClear: 'Clear',
  cacheClearing: 'Clearing\u2026',
  cacheConfirmNote:
      'These files go to the recycle bin, so they can be restored if needed.',
  cacheConfirmOk: 'Clear now',
  cacheNoPermission: 'the rest are in use or not permitted',
  cacheCountSize: '{count} files / {size}',
  top5Title: 'Top 5 / Top 10',
  top5StepSelect: 'Select',
  top5StepPreview: 'Preview & narration',
  top5LevelWeek: 'Week',
  top5LevelMonth: 'Month',
  top5LevelYear: 'Year',
  top5KindGoal: 'Goals',
  top5KindSave: 'Saves',
  top5ThisWeek: 'this week',
  top5ThisMonth: 'this month',
  top5ThisYear: 'this year',
  top5PoolTitle: 'Available clips',
  top5PoolEmptyWeek: 'This project has no clips yet. Monthly and yearly reels can pick from the weekly/monthly reels you already saved.',
  top5PoolEmptyMonth: 'No weekly reel to pick from yet. Make a weekly reel first.',
  top5PoolEmptyYear: 'No monthly reel to pick from yet. Make a monthly reel first.',
  top5RanksTitle: 'Ranking',
  top5RanksHint: 'No. 1 = best',
  top5MoveUp: 'Move up',
  top5MoveDown: 'Move down',
  top5Remove: 'Remove',
  top5PreviewHint: 'Press ▶ on the right to preview the clip',
  top5VoiceLabel: 'Narration voice',
  top5NoVoices: 'No voice or voice pack on this machine',
  top5VoiceHint: 'Choose a voice',
  top5CreatePack: 'Create voice pack',
  top5Import: 'Import',
  top5VoiceGuide: 'Voice pack guide',
  top5PreviewClip: 'Preview clip',
  top5CommentHint: 'Narration · read over the clip',
  top5Audition: 'Audition this line',
  top5PlayTake: 'Play the last audition',
  top5TakeMissing: 'No audition kept yet — press “Audition this line” first',
  top5SeedHint: 'Seed of this take: type it into the studio to hear it again',
  top5PreviewNoPicture:
      'The picture did not come out (logged). Press ▶ again to reload the player.',
  top5ReloadingPlayer: 'Reloading the player…',
  top5Seed: 'seed',
  top5SeedInvalid: 'seed must be an integer between 0 and 4294967295',
  top5SeedRange: 'range 0 – 4294967295, default 50',
  top5FooterDone: 'Rendered · change the voice or a comment and press Regenerate',
  top5FooterNarrate: 'Narration is stored on the entry, it never appears on screen',
  top5Next: 'Next',
  top5Watch: 'Watch',
  top5Regenerate: 'Regenerate',
  top5Back: 'Back',
  top5NoComment: 'No narration yet',
  top5NeedComment: 'Write the narration first',
  top5NeedVoice: 'Choose a narration voice first',
  top5CloneFailed: 'Cloning failed',
  top5PreparingClip: 'Preparing the clip…',
  top5ClipNoPreview: 'This clip cannot be previewed',
  top5LoadingPlayer: 'Loading the player…',
  top5NeedBgm: 'Pick a background music template in the template panel first',
  top5BusyPrepare: 'Preparing clips',
  top5NextTime: 'See you next time',
  top5CoverTitle: 'Top 5 / Top 10',
  top5ClipNoVideo: 'This clip has no usable video file',
  top5SliceUnplayable: 'The slice is not playable',
  top5SliceFailedShort: 'Slicing failed',
  top5VoiceRefreshed: 'Voice list refreshed',
  top5ImportTitle: 'Import a voice pack',
  top5ImportFolder: 'Choose a .voicepack folder',
  top5ImportAudio: 'Choose a recording (packed for you)',
  top5PickPackFolder: 'Choose a voice pack folder',
  top5FolderNoAudio: 'That folder has no usable audio',
  top5FolderOneAudio: 'The folder needs exactly one audio file, or pick a .voicepack directly',
  top5ImportFailedShort: 'Import failed',
  top5StudioMissing: 'This plugin has no Voice Studio (incomplete install). Run tools\\voice_clone\\setup.bat to add it.',
  top5EngineMissing: 'The local cloning engine is not installed (no voice_clone folder).',
  top5EngineNotInstalled:
      'The local cloning engine is not installed. Run tools\\voice_clone\\setup.bat once to add it.',
  top5EngineMissingHint: 'The “use my own voice” section below needs that engine.',
  menuPhoneMarking: 'Phone marking',
  phoneMarkingTitle: 'Phone marking',
  phoneMarkingScan: 'Scan the QR code with your phone',
  phoneMarkingAddress: 'Address',
  phoneMarkingToken: 'Token',
  phoneMarkingOpen: 'Open',
  phoneMarkingStop: 'Stop',
  phoneMarkingRunning: 'Server running',
  phoneMarkingStopped: 'Server stopped',
  phoneMarkingNoSources: 'The open project has no sources yet.',
  phoneMarkingLocalhostHint:
      'No LAN address found — falling back to localhost, which a phone cannot reach.',
  phoneMarkingStartFailed: 'Could not start the server: ',
  phoneMarkingFirewallHint:
      'The phone must be on the same Wi-Fi as the PC. If Windows asks about the firewall on first listen, allow it on private networks.',
  phoneMarkingPageTitle: 'Phone marking',
  phoneMarkingPageSources: 'Sources',
  phoneMarkingPagePlayer: 'Pick a source above — its proxy plays here.',
  phoneMarkingPagePreparing: 'Preparing the proxy',
  phoneMarkingPageFailed: 'The proxy failed — reload the page to retry.',
  menuAiMarking: 'AI marking',
  aiTitle: 'AI marking',
  aiApiKey: 'DeepSeek API key',
  aiRememberKey: 'Remember',
  aiShowKey: 'Show',
  aiHideKey: 'Hide',
  aiModel: 'Model',
  aiPickVideo: 'Choose match video',
  aiNoFile: 'No file chosen',
  aiSupportedFormats: 'mp4 / mov / mkv',
  aiUnsupportedFormat: 'Only mp4 / mov / mkv are supported.',
  aiStart: 'Analyse',
  aiReanalyze: 'Analyse again',
  aiStageAudio: 'Extracting audio',
  aiStageMotion: 'Scanning screen motion',
  aiStageDetect: 'Finding candidates',
  aiStageJudge: 'Judging',
  aiStageDone: 'Done',
  aiResultsTitle: 'Candidates',
  aiVerdictHighlight: 'Highlight',
  aiVerdictOrdinary: 'Ordinary',
  aiVerdictUnjudged: 'Not judged',
  aiView: 'View',
  aiSaveProject: 'Save as project',
  aiUnsupportedBanner:
      'This model does not accept image input, so only the candidates were kept (not judged by AI).',
  aiInvalidKey: 'The API key is invalid; analysis stopped.',
  aiNoHighlight: 'No candidate passed, so no project file was written.',
  aiNeedKey: 'Enter an API key first.',
  aiNeedFile: 'Choose a video first.',
  aiNoFfmpeg: 'ffmpeg was not found, so nothing can be analysed.',
  aiMotionUnavailable:
      'Screen-motion analysis is unavailable, so this run uses sound only.',
  aiCancelled: 'Cancelled.',
  aiSavedTo: 'Saved to ',
  aiNoFileHighlights: 'No highlights detected',
  aiFileSkipped: 'Skipped (analysis failed)',
  aiCalibrateGoal: 'Calibrate goals',
  goalCalibTitle: 'Goal calibration',
  goalCalibHint:
      'Drag on the frame to box each goal — up to two. A third drag replaces the second.',
  goalCalibEmpty: 'No goal boxed yet — drag on the frame.',
  goalCalibClear: 'Clear',
  goalCalibSave: 'Save',
  goalCalibApplySiblings: 'Apply to every video in this folder',
  goalCalibNoFrame: 'No frame could be read, so calibration is unavailable.',
  goalCalibSaveFailed: 'Saving the calibration failed, so it will not be used.',
  goalCalibLoading: 'Reading a frame',
);

const _zh = AppStrings(
  openVideoFile: '打开视频文件',
  noProject: '无项目',
  settings: '设置',
  newProjectTitle: '新建项目',
  projectNameHint: '项目名称',
  cancel: '取消',
  cancelBtn: '取消',
  create: '创建',
  save: '保存',
  ok: '确定',
  okBtn: '确定',
  close: '关闭',
  editDescription: '编辑描述',
  delete: '删除',
  unsavedChanges: '未保存的更改',
  unsavedChangesMessage: '您有未保存的更改。是否在继续之前保存？',
  discard: '放弃',
  updateAvailableTitle: '发现新版本',
  updateAvailableMessage: 'Microsoft Store 上有新版本的 Highlight Creator 可用。',
  updateNow: '去更新',
  updateLater: '以后再说',
  projectMenu: '项目',
  saveProject: '保存项目',
  loadProject: '加载项目',
  closeProject: '关闭项目',
  timeslots: '时间片段',
  colNumber: '#',
  colDescription: '描述',
  colFilename: '文件名',
  colTime: '时间',
  colElapse: '耗时',
  colRemote: '放大远端画面',
  colRemoteShort: '远端',
  colRating: '★',
  colColor: '颜色',
  noTimeslotsYet: '暂无时间片段。',
  useMarkButton: '使用标记按钮添加。',
  slotPrefix: '片段 ',
  editAction: '编辑',
  deleteAction: '删除',
  remoteTooltip: '远端（放大）',
  localTooltip: '本地',
  seekBack: '后退5秒 (←)',
  playPause: '播放/暂停 (空格)',
  seekForward: '前进5秒 (→)',
  stop: '停止 (Esc)',
  mark: '标记 (Ctrl+M)',
  markTooltip: '标记精彩片段',
  speed: '速度',
  make: '制作',
  makingHighlight: '正在制作精彩集锦...',
  doneOutput: '完成！输出: ',
  makeFailed: '制作失败: ',
  markTimeslot: '标记时间片段',
  descriptionHint: '描述',
  remote: '放大远端画面',
  timeslotMarked: '时间片段已标记',
  failedToMark: '标记失败: ',
  startupTemplate: '开场模板',
  transitionTemplate: '转场模板',
  endingTemplate: '结尾模板',
  backgroundMusic: '背景音乐',
  addTemplate: '添加模板',
  noTemplates: '未配置模板。',
  preview: '预览',
  bgMusicFile: '背景音乐文件: ',
  missingTemplateFiles: '缺少模板文件',
  templateFileNotFound: '模板文件未找到:',
  deleteTemplateTitle: '删除模板',
  deleteTemplateConfirm: '删除 {name}？',
  editTitle: '编辑标题',
  sourceFiles: '源文件',
  addVideoFiles: '添加视频文件',
  addVideoFilesShort: '添加视频文件',
  failedToAddFiles: '添加文件失败: ',
  noVideoFiles: '无视频文件',
  clickToAdd: '点击 + 添加',
  removeFromList: '从列表移除',
  projectPrefix: '项目: ',
  sourceFilesSuffix: ' 个源文件',
  timeslotsSuffix: ' 个时间片段',
  videoInfoPlaceholder: '1920×1080 · H.264 · 30fps',
  appVersion: 'Highlight Creator v0.4.1.0',
  noVideoLoaded: '未加载视频',
  openVideo: '打开视频',
  unknownError: '未知错误',
  dismiss: '关闭',
  settingsTitle: '设置',
  languageSection: '语言',
  languageLabel: '语言',
  aboutSection: '关于',
  appName: 'Highlight Creator',
  appVersionInfo: '版本 0.4.1.0',
  selectLanguage: '选择语言',
  failedToOpenVideo: '打开视频失败: ',
  projectSaved: '项目已保存。',
  projectLoaded: '项目已加载。',
  projectClosed: '项目已关闭。',
  projectCleared: '项目已清空。',
  hlcprojFilter: 'Highlight Creator 项目',
  noProjectToSave: '没有可保存的项目。',
  saveFailed: '保存失败: ',
  loadFailed: '加载失败: ',
  zoomInPointTitle: '设置放大的画面中心',
  zoomApplyToAll: '应用到所有',
  zoomNext: '下一步',
  zoomDone: '完成',
  zoomTimeslotOf: '时间片段',
  zoomFailedLoadFrame: '无法加载画面',
  renderDialogTitle: '正在渲染\u2026',
  renderDialogMessage: '正在创建精彩集锦视频，请稍候',
  outputResolution: '输出分辨率',
  resolutionNotAvailable: '不可用（高于源分辨率）',
  resultFolder: '打开成品文件夹',
  previewDialogTitle: '预览与确认',
  previewStartupSection: '开场',
  previewTransitionSection: '转场',
  previewEndingSection: '结尾',
  previewNoEnding: '未配置结尾',
  previewConfirm: '确认并制作',
  previewTimeslotCount: '个时间片段',
  previewTotalElapse: '总时长: ',
  autoGen: 'AI辅助生成',
  autoGenTooltip: '利用本地算法协助剪辑视频中的高光时刻，仍需要人工甄别，安全，免费。注意：对硬件有一定要求，低配硬件可能会非常慢！',
  autoGenNeedSource: '请先添加视频源文件。',
  autoGenComingSoon: 'AI辅助生成功能即将推出，敬请期待。',
  timeline: '时间轴',
  translate: '语音转文字',
  translating: '正在转换音频...',
  translateDone: '转换完成: ',
  translateFailed: '转换失败: ',
  guideTitle: '新手指引',
  guidePrev: '上一步',
  guideNext: '下一步',
  guideDone: '完成',
  guideDontShowAgain: '以后不再自动弹出',
  helpSection: '帮助',
  wantToMenu: '我要',
  guideStep1: '在源文件中点击添加按钮，添加视频文件',
  guideStep2: '播放视频文件过程中，点击标记按钮，记录精彩时刻',
  guideStep3: '添加文字描述用于转场，勾选放大选择框如果需要放大远端画面',
  guideStep4: '添加个性片头或者使用内置片头',
  guideStep5: '添加个性转场或者使用内置转场',
  guideStep6: '添加个性片尾或者使用内置片尾',
  guideStep7: '添加个性背景音乐或者使用内置背景音乐',
  guideStep8: '使用「我要」\u2192「制作」，选择输出分辨率，等待成片完成',
  wantMake: '制作',
  wantGoTo: '跳转到指定时间',
  gotoTitle: '跳转到指定时间',
  gotoDestTime: '目标时间 (时:分:秒)',
  gotoBaseTime: '基准时间（可选，时:分:秒）',
  gotoGo: '跳转',
  gotoBadTime: '时间格式无效，请使用 时:分:秒',
  gotoNoSource: '项目中没有源视频',
  gotoSeeked: '已跳转至 ',
  gotoClamped: '（超出总时长，已截断到结尾）',
  hotkeySection: '快捷键',
  hotkeyTitle: '快捷键列表',
  hotkeyNameMark: '标记',
  hotkeyNameSeekBack: '后退5秒',
  hotkeyNameSeekForward: '前进5秒',
  hotkeyNamePlayPause: '播放 / 暂停',
  hotkeyNameGoTo: '跳转到指定时间',
  hotkeyNameSave: '保存项目',
  hotkeyNameNew: '新建项目',
  hotkeyNameOpen: '打开项目',
  hotkeyNameClose: '关闭项目',
  hotkeyNameAddSource: '添加视频源',
  hotkeyNameTemplates: '模板配置',
  code: 'zh',
  menuTop5: '5佳球 / 10佳球',
  menuCache: '查看缓存',
  menuClipBreakdown: '时间片段分类明细',
  commonCancel: '取消',
  commonRefresh: '刷新',
  commonClose: '关闭',
  commonGotIt: '知道了',
  voiceGuideTitle: 'Windows 语音包安装指南',
  voiceGuideIntro:
      '解说语音完全在本机合成,不联网、不需要 key。Windows 自带的中文语音包偏机械,想要更自然的效果,按下面任一路径下载「自然语音」。',
  voiceGuideStep1:
      '设置 → 辅助功能 → 讲述人 → 添加语音 → 下载「中文(简体)」的自然语音(微软晓晓 / 晓伊 / 云希等)',
  voiceGuideStep2:
      '设置 → 时间和语言 → 语言和区域 → 中文(简体) → 语言选项 → 语音 → 下载语音包',
  voiceGuideAfter: '装好后回到本应用点「刷新」即可看到新语音;如果列表没变,重启一次应用。',
  voiceGuideOwnTitle: '用我自己的声音',
  voiceGuideOwnBody:
      '点「创建语音包」会打开语音工作室（一个独立的录音程序）。照着提示词读完、试听满意后保存，回到这里「解说语音」里就多出一个语音包。',
  voiceGuideOwnImport:
      '也可以点「导入」，直接拿别人给的 .voicepack 文件夹，或者一个录音文件。',
  voiceGuideEngine:
      '克隆本身需要本地引擎（Python + 显卡），不随安装包附带: 运行 tools\\voice_clone\\setup.bat 装一次，之后全程离线，音频不出本机。',
  voiceGuideNarrator: '打开讲述人语音设置',
  voiceGuideLanguage: '打开语言语音包设置',
  cacheTitle: '缓存文件',
  cacheSlicesName: '五佳球切片缓存',
  cacheSlicesWhat: '每个时间槽的一份干净切片，预览和生成共用；清空后下次自动重切，只是慢一点。',
  cacheNarrationName: '五佳球配音',
  cacheNarrationWhat: 'TTS / 克隆 / 试听生成的音频，含每条解说最后一次试听的版本，渲染后即可清理。',
  cacheWorkName: '五佳球渲染中间文件',
  cacheWorkWhat: '排名卡、转场、片段和拼接用的 master，拼接后就没用了。',
  cacheTemplatesName: '内置模板视频',
  cacheTemplatesWhat: '转场 / 开场 / 结尾模板，首次使用时自动渲染；清空后下次要重新生成几分钟。',
  cacheMakeName: 'Make 渲染中间产物',
  cacheMakeWhat: '每次 Make 都会重做。清空后 5佳球 不再复用它们，改为从源视频切（稍慢）。',
  cacheEmpty: '空',
  cacheOpen: '打开',
  cacheClear: '清空',
  cacheClearing: '清空中…',
  cacheConfirmNote: '这些文件会进回收站，需要的话可以还原。',
  cacheConfirmOk: '确定清空',
  cacheNoPermission: '其余的被占用或没有权限',
  cacheCountSize: '{count} 个 / {size}',
  top5Title: '5佳球 / 10佳球',
  top5StepSelect: '选择',
  top5StepPreview: '预览与解说',
  top5LevelWeek: '周',
  top5LevelMonth: '月',
  top5LevelYear: '年',
  top5KindGoal: '进球',
  top5KindSave: '扑救',
  top5ThisWeek: '本周',
  top5ThisMonth: '本月',
  top5ThisYear: '本年',
  top5PoolTitle: '可选片段',
  top5PoolEmptyWeek: '当前项目还没有片段 · 月度和年度可以用已保存的周/月条目',
  top5PoolEmptyMonth: '还没有周度成片可以选 · 先做一期周度',
  top5PoolEmptyYear: '还没有月度成片可以选 · 先做一期月度',
  top5RanksTitle: '名次',
  top5RanksHint: 'NO.1 = 最佳',
  top5MoveUp: '上移',
  top5MoveDown: '下移',
  top5Remove: '移出',
  top5PreviewHint: '点右侧 ▶ 预览片段',
  top5VoiceLabel: '解说语音',
  top5NoVoices: '本机没有可用的语音或语音包',
  top5VoiceHint: '选择语音',
  top5CreatePack: '创建语音包',
  top5Import: '导入',
  top5VoiceGuide: '语音包指南',
  top5PreviewClip: '预览片段',
  top5CommentHint: '解说 · 成片里念出来',
  top5Audition: '试听这句解说',
  top5PlayTake: '播放上次试听',
  top5TakeMissing: '还没有可播放的试听版本,先点「试听这句解说」',
  top5SeedHint: '这一版的 seed:填到语音工作室里可以复现同一版',
  top5PreviewNoPicture: '画面没有出来(已记录日志),再点一次 ▶ 重新加载播放器',
  top5ReloadingPlayer: '重新加载播放器…',
  top5Seed: 'seed',
  top5SeedInvalid: 'seed 必须是 0 – 4294967295 之间的整数',
  top5SeedRange: '范围 0 – 4294967295，默认 50',
  top5FooterDone: '已生成 · 不满意可以换语音/改解说后点「重新生成」',
  top5FooterNarrate: '解说保存在条目里,渲染时不出现在画面上',
  top5Next: '下一步',
  top5Watch: '观看',
  top5Regenerate: '重新生成',
  top5Back: '返回',
  top5NoComment: '未填解说词',
  top5NeedComment: '请先填写解说词',
  top5NeedVoice: '请先选择解说语音',
  top5CloneFailed: '克隆失败',
  top5PreparingClip: '正在准备片段…',
  top5ClipNoPreview: '这个片段无法预览',
  top5LoadingPlayer: '正在加载播放器…',
  top5NeedBgm: '请先在模板面板选择背景音乐模板',
  top5BusyPrepare: '准备片段',
  top5NextTime: '下期见',
  top5CoverTitle: '5佳球 / 10佳球',
  top5ClipNoVideo: '这个片段没有可用的视频文件',
  top5SliceUnplayable: '切片生成的文件无法播放',
  top5SliceFailedShort: '切片失败',
  top5VoiceRefreshed: '语音列表已刷新',
  top5ImportTitle: '导入语音包',
  top5ImportFolder: '选择一个 .voicepack 文件夹',
  top5ImportAudio: '选择一个录音文件（自动打包）',
  top5PickPackFolder: '选择语音包文件夹',
  top5FolderNoAudio: '这个文件夹里没有可用的音频',
  top5FolderOneAudio: '文件夹里需要恰好一个音频文件，或者直接选一个 .voicepack',
  top5ImportFailedShort: '导入失败',
  top5StudioMissing: '当前插件里没有语音工作室（安装不完整）。重跑 tools\\voice_clone\\setup.bat 即可补上。',
  top5EngineMissing: '本机还没有安装本地克隆引擎（voice_clone 目录不在）。',
  top5EngineNotInstalled: '本地克隆引擎未安装,请先运行 tools\\voice_clone\\setup.bat',
  top5EngineMissingHint: '下面「用我自己的声音」这一节要装好引擎才能用。',
  menuPhoneMarking: '手机打点',
  phoneMarkingTitle: '手机打点',
  phoneMarkingScan: '用手机扫描二维码打开',
  phoneMarkingAddress: '监听地址',
  phoneMarkingToken: '令牌',
  phoneMarkingOpen: '打开',
  phoneMarkingStop: '停止',
  phoneMarkingRunning: '服务运行中',
  phoneMarkingStopped: '服务已停止',
  phoneMarkingNoSources: '当前项目还没有片源。',
  phoneMarkingLocalhostHint: '没有找到局域网地址，已回退到 localhost；手机无法访问。',
  phoneMarkingStartFailed: '启动失败: ',
  phoneMarkingFirewallHint:
      '手机需要和电脑在同一个 Wi-Fi。Windows 首次提示防火墙时，请允许「专用网络」。',
  phoneMarkingPageTitle: '手机打点',
  phoneMarkingPageSources: '片源',
  phoneMarkingPagePlayer: '点上面的片源，代理视频在这里播放。',
  phoneMarkingPagePreparing: '正在生成代理',
  phoneMarkingPageFailed: '代理生成失败，刷新页面重试。',
  menuAiMarking: 'AI 打点',
  aiTitle: 'AI 打点',
  aiApiKey: 'DeepSeek API Key',
  aiRememberKey: '记住',
  aiShowKey: '显示',
  aiHideKey: '隐藏',
  aiModel: '模型',
  aiPickVideo: '选择比赛视频',
  aiNoFile: '未选择文件',
  aiSupportedFormats: '支持 mp4 / mov / mkv',
  aiUnsupportedFormat: '只支持 mp4 / mov / mkv。',
  aiStart: '开始分析',
  aiReanalyze: '重新分析',
  aiStageAudio: '抽音频',
  aiStageMotion: '算画面运动',
  aiStageDetect: '找候选',
  aiStageJudge: '逐段判定',
  aiStageDone: '完成',
  aiResultsTitle: '候选片段',
  aiVerdictHighlight: '高光',
  aiVerdictOrdinary: '普通',
  aiVerdictUnjudged: '未判定',
  aiView: '查看',
  aiSaveProject: '保存为项目',
  aiUnsupportedBanner: '该模型不支持图片输入，已只保留候选（未经 AI 判定）',
  aiInvalidKey: 'API Key 无效，已停止分析。',
  aiNoHighlight: '没有判定为高光的候选，未写出项目文件。',
  aiNeedKey: '请先填写 API Key。',
  aiNeedFile: '请先选择视频文件。',
  aiNoFfmpeg: '找不到 ffmpeg，无法分析。',
  aiMotionUnavailable: '画面运动不可用，仅用声音。',
  aiCancelled: '已取消。',
  aiSavedTo: '已保存到 ',
  aiNoFileHighlights: '无检出高光',
  aiFileSkipped: '已跳过（分析失败）',
  aiCalibrateGoal: '标定球门',
  goalCalibTitle: '球门标定',
  goalCalibHint: '在画面上拖动框出球门，最多 2 个；再拖会替换第 2 个。',
  goalCalibEmpty: '还没有框选球门：在画面上拖动。',
  goalCalibClear: '清除',
  goalCalibSave: '保存',
  goalCalibApplySiblings: '应用到同目录所有视频',
  goalCalibNoFrame: '无法取帧，标定不可用',
  goalCalibSaveFailed: '保存标定失败，本次不会使用它。',
  goalCalibLoading: '正在取帧',
);

/// Reactive provider: current language string ('English' or '中文').
/// Watching this will rebuild the widget tree when language changes.
class LanguageNotifier extends StateNotifier<String> {
  final SettingsService _svc;

  LanguageNotifier(this._svc) : super('English') {
    _load();
  }

  Future<void> _load() async {
    final lang = await _svc.language;
    // The file read can resolve after this notifier was disposed (app
    // shutdown, or a ProviderContainer torn down at the end of a test);
    // writing state then throws and surfaces as a stray async error.
    if (mounted) state = lang;
  }

  Future<void> setLanguage(String lang) async {
    state = lang;
    await _svc.setLanguage(lang);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, String>(
  (ref) => LanguageNotifier(ref.watch(settingsServiceProvider)),
);

/// Derived provider: current [AppStrings].
final l10nProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(languageProvider);
  return lang == '中文' ? _zh : _en;
});
