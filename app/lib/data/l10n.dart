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
  appVersion: 'Highlight Creator v0.1.4.0',
  noVideoLoaded: 'No video loaded',
  openVideo: 'Open Video',
  unknownError: 'Unknown error',
  dismiss: 'Dismiss',
  settingsTitle: 'Settings',
  languageSection: 'Language',
  languageLabel: 'Language',
  aboutSection: 'About',
  appName: 'Highlight Creator',
  appVersionInfo: 'Version 0.1.4.0',
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
  appVersion: 'Highlight Creator v0.1.4.0',
  noVideoLoaded: '未加载视频',
  openVideo: '打开视频',
  unknownError: '未知错误',
  dismiss: '关闭',
  settingsTitle: '设置',
  languageSection: '语言',
  languageLabel: '语言',
  aboutSection: '关于',
  appName: 'Highlight Creator',
  appVersionInfo: '版本 0.1.4.0',
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
