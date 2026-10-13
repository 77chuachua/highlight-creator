// Authoring tool for the "aurora" online template set.
//
// Emits the three single-line ffmpeg filtergraphs the catalogue publishes:
//
//   aurora-startup.ffscript     4.0 s intro
//   aurora-ending.ffscript      3.0 s outro (light retreats)
//   aurora-transition.ffscript  1.5 s wipe with a reserved text zone
//
// The look imitates the built-in 'nocturne' design set
// (app/lib/data/ffi/video_processing_service.dart, _nocturneLayers): a night
// stadium built in depth — graded indigo sky, a hairline horizon, a mowed pitch
// in faked perspective, an anamorphic streak along the horizon and one hairline
// graphic layer with a single accent. Only the light moves; the ground does
// not, which is what makes the light read as light.
//
// What is new: nocturne's three raking floodlight shafts become three rippling
// aurora curtains, and the graphic accent is mint instead of amber.
//
// Run from template_hub/:   dart gen_aurora.dart
import 'dart:io';

void main() {
  final graphs = <String, String>{
    'aurora-startup.ffscript': _startup(4.0),
    'aurora-ending.ffscript': _ending(3.0),
    'aurora-transition.ffscript': _transition(1.5),
  };
  for (final e in graphs.entries) {
    File(e.key).writeAsStringSync('${e.value}\n');
    stdout.writeln('${e.key}: ${e.value.length} chars');
  }
}

// ------------------------------------------------------------------ primitives
// Same shapes as the built-in scene helpers so the emitted graph is the same
// language the app already renders (and the same escaping: `\,` inside geq).

String _ramp(double a, double b) {
  final w = (b - a).toStringAsFixed(3);
  return 'min(max((T-$a)/$w\\,0)\\,1)';
}

/// Smoothstep between [t0] and [t1] on the geq clock [t].
String _ease(String t, double t0, double t1) {
  final w = (t1 - t0).toStringAsFixed(3);
  final u = 'min(max(($t-$t0)/$w\\,0)\\,1)';
  return '($u)*($u)*(3.0-2.0*($u))';
}

String _win(double si, double ei, double so, double eo) =>
    'min(${_ramp(si, ei)}\\,(1-${_ramp(so, eo)}))';

String _line(String v, double th) =>
    'max(0\\,1-abs($v)/${th.toStringAsFixed(1)})';

String _c01(String e) => 'min(max($e\\,0)\\,1)';

/// Evaluate [expr] into geq slot [slot] and contribute nothing to the value.
/// geq has no statement form, so the store rides along the surrounding sum
/// multiplied by zero. Slots 0-3 are the light rig, 4+ the graphic layers.
String _slot(int slot, String expr) => '(st($slot,$expr)*0)';

String _rect(String cx, String cy, String hw, String hh, String s) =>
    '(${_c01('(($hw)-abs(X-($cx)))/$s')})*'
    '(${_c01('(($hh)-abs(Y-($cy)))/$s')})';

// --------------------------------------------------------------------- palette
const _sky = <int>[4, 10, 18];
const _ground = <int>[10, 26, 30];
const _streakCol = <int>[58, 92, 110];
const _poolCol = <int>[15, 33, 32];
const _mowCol = <int>[3, 8, 7];
const _accent = <String>['138', '226', '196']; // mint hairline accent
const _plate = <String>['16', '30', '34'];

/// (base x, half width, amplitude, sway phase) of the three curtains. Three
/// weights, not three identical ribbons, so the sky has a rhythm. Narrow on
/// purpose: three wide ones overlap into a single horizontal wash, which reads
/// as a glow rather than as curtains.
const _curtainSpec = <(double, double, double, double)>[
  (0.26, 0.028, 1.00, 0.00),
  (0.52, 0.021, 0.62, 2.10),
  (0.72, 0.016, 0.38, 4.30),
];

/// Per-curtain tint: aurora green, cyan, violet. Kept dim enough that the three
/// summing in one channel stay under the 250 ceiling — a clamped curtain is a
/// white curtain, and the green is the whole point.
const _curtainCol = <List<int>>[
  [40, 126, 92],
  [28, 88, 146],
  [78, 58, 136],
];

// ------------------------------------------------------------------ the scene
const _hzn = 'H*0.66';

/// (layers, base) where layers are (mask, alpha, [r,g,b]) and base is the
/// per-channel pixel expression before the graphic fold — the same contract
/// [_nocturneLayers] uses.
(List<(String, String, List<String>)>, List<String>) _scene(
  double d, {
  required bool withPlate,
  bool settle = false,
}) {
  // Ground: identical to nocturne's, because the ground is the part that must
  // not move. The depth ramp gates the pitch and doubles as the perspective
  // divisor for the mow stripes, so they converge on the horizon.
  const dp = 'min(max((Y-$_hzn)/(H*0.22)\\,0)\\,1)';
  const persp = '(0.13+0.87*$dp)';
  const mow = '(1-2*gt(mod((X-W/2)/(W*0.05*$persp)\\,2)\\,1))*($dp*$dp)';

  // Anamorphic streak along the horizon: hot core inside a wide dim tail.
  const streakV = 'max(0\\,1-abs(Y-$_hzn-H*0.005)/(H*0.075))';
  const streakH1 = 'max(0\\,1-abs(X-W/2)/(W*0.46))';
  const streakH2 = 'max(0\\,1-abs(X-W/2)/(W*0.80))';
  const streakShape = '($streakV*$streakV*($streakH1*$streakH1'
      '+$streakH2*0.35))';

  // The lit ellipse of pitch the curtains land on.
  const qx = '((X-W/2)/(W*0.54))';
  const qy = '((Y-H*0.80)/(H*0.34))';
  const poolShape = 'max(0\\,1-$qx*$qx-$qy*$qy)';

  const vx = '((X-W/2)/(W*0.62))';
  const vy = '((Y-H/2)/(H*0.62))';
  const vig = '(1-0.12*($vx*$vx+$vy*$vy))';

  // Light only: eases up over the intro, dims and retreats over the outro.
  final lit = settle
      ? '(0.30+0.70*(1-${_ease('T', 0.10, d)}))'
      : _ease('T', 0.05, 1.60);
  // How far the curtains have descended. 1 = fully hung across the sky, ~0.38
  // = retreated upward and shortened, which is what the outro does.
  final hang = settle
      ? '(1-0.62*${_ease('T', 0.15, d)})'
      : _ease('T', 0.12, 2.20);
  final hangY = '(H*(0.12+0.30*$hang))';
  final hangH = '(H*(0.20+0.34*$hang))';

  String curtainSum(int k) {
    final out = <String>[];
    for (var i = 0; i < _curtainSpec.length; i++) {
      final s = _curtainSpec[i];
      // Slot 1 = the ribbon's centre for this row. It is a sine of height and
      // time, so the curtain ripples as it sways instead of sliding as a bar.
      final cx = 'W*${s.$1}'
          '+W*0.045*sin(2*PI*(Y/H)*1.35+2*PI*T/${d.toStringAsFixed(2)}'
          '+${s.$4})';
      // Slot 0 = the hanging band's centre row, slot 2 its half height: the
      // envelope is a soft vertical band that is clipped at the horizon so the
      // pitch stays unlit ground, and shortens as the curtains retreat.
      final env = 'max(0\\,1-abs(Y-ld(0))/ld(2))'
          '*${_c01('($_hzn-Y)/(H*0.10)')}';
      final perp = 'abs(X-ld(1))';
      final wd = 'W*${s.$2}';
      final core = 'max(0\\,1-$perp/$wd)';
      final halo = 'max(0\\,1-$perp/($wd*2.8))';
      // Vertical striations: real aurora is a bundle of rays, not a slab.
      final striate = '(0.74+0.26*sin((X-ld(1))*0.07+T*0.8))';
      final amp = (s.$3 * _curtainCol[i][k]).toStringAsFixed(2);
      final body =
          '(($core*$core+$halo*$halo*$halo*0.10)*$striate*$env*$amp)';
      out.add('${_slot(1, cx)}+$body');
    }
    return '${_slot(0, hangY)}+${_slot(2, hangH)}+${out.join('+')}';
  }

  final base = <String>[];
  for (var k = 0; k < 3; k++) {
    final grad = '${_sky[k]}+${(_ground[k] - _sky[k])}.0*(Y/H)';
    final light = '${curtainSum(k)}'
        '+${_streakCol[k]}.0*$streakShape'
        '+${_poolCol[k]}.0*$poolShape*$poolShape*$dp'
        '+${_mowCol[k]}.0*$mow';
    // Hard ceiling before the write-back: geq wraps mod 256 rather than
    // clamping, so one hot pixel (this scene sums three curtains + streak +
    // pool) would wrap into a band of garbage. Cap first, grain after.
    base.add('min(250.0\\,max(0.0\\,($grad+$lit*($light))*$vig))'
        '+(random($k)-0.5)*4.5');
  }

  // --- Graphic layer: one hairline system, one accent, one weight. ---
  final bandWin = _win(0.55, 1.35, d - 0.85, d);
  final wipe = _c01('(W*0.34*${_ease('T', 0.55, 1.35)}-abs(X-W/2))'
      '/(W*0.09)');
  final bracketWin = _win(0.75, 1.55, d - 0.75, d);
  final railWin = _win(0.10, 0.80, d - 0.70, d);

  String corner(String cx, String cy, double sx, double sy) {
    const len = 'W*0.070';
    final hSeg = '${_line('Y-$cy', 1.4)}'
        '*${_c01('($len-abs(X-($cx+$sx*$len*0.5)))/2.5')}';
    final vSeg = '${_line('X-$cx', 1.4)}'
        '*${_c01('($len*0.62-abs(Y-($cy+$sy*$len*0.31)))/2.5')}';
    return '(($hSeg)+($vSeg))';
  }

  const bx0 = 'W*0.048';
  const bx1 = 'W*0.952';
  const by0 = 'H*0.085';
  const by1 = 'H*0.915';
  const bandH = 'H*0.132';

  final brackets = _c01('(${corner(bx0, by0, 1, 1)})'
      '+(${corner(bx1, by0, -1, 1)})'
      '+(${corner(bx0, by1, 1, -1)})'
      '+(${corner(bx1, by1, -1, -1)})');
  final rail = _c01('${_line('Y-$_hzn', 1.3)}'
      '*(0.55+0.45*${_line('mod(X+W/32\\,W/16)-W/32', 1.0)}'
      '*${_c01('(H*0.020-abs(Y-$_hzn))/(H*0.008)')})'
      '*${_c01('(W*0.94-abs(X-W/2))/(W*0.26)')}');

  final layers = <(String, String, List<String>)>[
    if (withPlate)
      (_c01(_rect('W/2', 'H*0.46', 'W*0.30', bandH, '14')),
          '(0.78)*($bandWin)*($wipe)', _plate),
    if (withPlate)
      (_c01('${_line('Y-(H*0.46-$bandH)', 1.4)}*($wipe)'),
          '(0.85)*($bandWin)', _accent),
    if (withPlate)
      (_c01('${_line('Y-(H*0.46+$bandH)', 1.1)}*($wipe)'),
          '(0.34)*($bandWin)', _accent),
    (brackets, '(0.46)*($bracketWin)', _accent),
    (rail, '(0.72)*($railWin)', _accent),
  ];
  return (layers, base);
}

/// Layer fold: `acc*(1-a)+color*a` per channel, with every alpha evaluated once
/// into its own geq slot and read back twice. That halves the filter string,
/// which is the difference between fitting the command line and not.
String _fold(List<(String, String, List<String>)> layers, List<String> base) {
  String channel(int k) {
    var acc = base[k];
    final stores = <String>[];
    for (var i = 0; i < layers.length; i++) {
      stores.add(_slot(4 + i, '(${layers[i].$1})*(${layers[i].$2})'));
      acc = '($acc)*(1-ld(${4 + i}))+(${layers[i].$3[k]})*ld(${4 + i})';
    }
    return '${stores.join('+')}+($acc)';
  }

  return "geq=r='${channel(0)}':g='${channel(1)}':b='${channel(2)}'";
}

String _clip(
  List<(String, String, List<String>)> layers,
  List<String> base, {
  required double fadeIn,
  required double fadeOutStart,
  required double fadeOut,
}) =>
    'format=rgb24,${_fold(layers, base)},format=yuv420p,'
    'scale=1280:720:flags=lanczos,fps=30,'
    'fade=t=in:st=0:d=$fadeIn,fade=t=out:st=$fadeOutStart:d=$fadeOut';

String _startup(double d) {
  final scene = _scene(d, withPlate: true);
  return _clip(scene.$1, scene.$2,
      fadeIn: 0.5, fadeOutStart: d - 0.6, fadeOut: 0.6);
}

String _ending(double d) {
  final scene = _scene(d, withPlate: true, settle: true);
  return _clip(scene.$1, scene.$2,
      fadeIn: 0.3, fadeOutStart: d - 0.8, fadeOut: 0.8);
}

/// The transition keeps the same reserved centre zone the built-in variants
/// use — darkened card plus a faint ring — so the centred overlay text stays
/// readable whatever is behind it. Outside the zone, three aurora bands sweep
/// past a horizon rail.
String _transition(double d) {
  const zoneIn = 'lt(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))\\,1)';
  const zoneRing =
      'lt(abs(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))-1)\\,0.018)';

  String band(double phase, double w, double amp) {
    final x = '(mod(W*1.5*(T/$d+$phase)\\,W*2.2)-W*0.6)';
    // A ripple along the band's length is what separates an aurora curtain
    // from the straight floodlight shaft nocturne's transition uses.
    final dist = 'abs((X-$x)-0.18*(Y-H*0.5)'
        '+W*0.020*sin(2*PI*(Y/H)*1.6+T*2.0))';
    return '${_line(dist, w)}'
        '*${_c01('(H*0.72-abs(Y-H*0.44))/(H*0.46)')}*$amp';
  }

  final rail = '${_line('Y-H*0.68', 1.6)}'
      '*88*${_win(0.10, 0.45, 1.05, 1.35)}';

  String channel(int k) {
    final dark = '${_sky[k]}+${(_ground[k] - _sky[k])}.0*0.35';
    final light = '${band(0.00, 30.0, (_curtainCol[0][k] * 0.34))}'
        '+${band(0.37, 19.0, (_curtainCol[1][k] * 0.25))}'
        '+${band(0.71, 12.0, (_curtainCol[2][k] * 0.16))}'
        '+$rail';
    final zone = '$dark*0.5+4+4*sin(2*PI*T/$d)';
    return 'if($zoneIn\\,$zone\\,if($zoneRing\\,${_ring[k]}\\,$dark+$light))';
  }

  final geq = "geq=r='${channel(0)}':g='${channel(1)}':b='${channel(2)}'";
  return 'format=rgb24,$geq,format=yuv420p,'
      'scale=1280:720:flags=lanczos,fps=30,'
      'fade=t=in:st=0:d=0.15,fade=t=out:st=${d - 0.2}:d=0.2';
}

/// Cool ring around the reserved zone, so the wipe reads as aurora light
/// rather than the built-in's neutral grey.
const _ring = <String>['150', '200', '205'];
