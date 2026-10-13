// Authoring tool for the "zenith" online template set.
//
// Emits the three single-line ffmpeg filtergraphs the catalogue publishes:
//
//   zenith-startup.ffscript     4.0 s intro
//   zenith-ending.ffscript      3.0 s outro (rig dims, text area only)
//   zenith-transition.ffscript  1.5 s wipe with a reserved text zone
//
// Same *materials* as the built-in 'nocturne' set — a night stadium built in
// depth, volumetric light through haze, film grain, smoothstep timing, hairlines
// as the only graphic language, and light-only motion over a ground that never
// moves. Everything else is deliberately different, so the two sets read as
// siblings rather than as recolours:
//
//   nocturne   three raking shafts from one implied source, mowed pitch,
//              horizon rail with a tick scale, amber corner brackets.
//   aurora     three rippling curtains, same pitch, mint brackets.
//   zenith     a 2x2 overhead rig casting near-vertical cones onto a *wet*
//              pitch (each pool smears downward into a reflection), no mowed
//              stripes and no corner brackets: the graphic layer is a
//              scoreboard bar — plate, one top rule, a tick scale under it,
//              two end caps and a plumb line up to the frame edge.
//
// Run from template_hub/:   dart gen_zenith.dart
import 'dart:io';

import 'scene_kit.dart';

void main() {
  final graphs = <String, String>{
    'zenith-startup.ffscript': _startup(4.0),
    'zenith-ending.ffscript': _ending(3.0),
    'zenith-transition.ffscript': _transition(1.5),
  };
  for (final e in graphs.entries) {
    File(e.key).writeAsStringSync('${e.value}\n');
    stdout.writeln('${e.key}: ${e.value.length} chars');
  }
}

// --------------------------------------------------------------------- palette
// Cold violet-graphite night with a white-blue rig and pale steel furniture.
// Nocturne is indigo + amber, aurora indigo-teal + mint; nothing here shares a
// hue with either, and the ground is wet rather than mown.
const _sky = <int>[5, 9, 18];
const _ground = <int>[16, 19, 34];
const _coneCol = <int>[104, 134, 192];
const _poolCol = <int>[78, 100, 150];
const _reflCol = <int>[64, 82, 126];
const _sheenCol = <int>[30, 36, 60];
const _glowCol = <int>[13, 16, 28]; // luminous ceiling around the rig
const _accent = <String>['186', '200', '222']; // pale steel hairlines
const _plate = <String>['24', '30', '46'];
const _ring = <String>['120', '136', '164'];

/// The rig: (lamp x, lamp y, pool y, cone half width, axis spread, amplitude,
/// phase) as fractions of the frame.
///
/// Two far lamps high and narrow, two near lamps lower and wider, so the array
/// itself is what sells the depth. Each lamp splays away from the centre
/// ([axis spread]) the way a real rig aims outward, which is also what puts its
/// pool where the cone actually lands.
const _lampSpec = <(double, double, double, double, double, double, double)>[
  (0.30, 0.10, 0.72, 0.032, -0.10, 1.00, 0.00),
  (0.70, 0.10, 0.72, 0.032, 0.10, 1.00, 3.14),
  (0.38, 0.17, 0.86, 0.044, -0.06, 0.86, 1.60),
  (0.62, 0.17, 0.86, 0.044, 0.06, 0.86, 4.70),
];

// ------------------------------------------------------------------ the scene
const _hzn = 'H*0.62';

Scene _scene(double d, {required bool withPlate, bool settle = false}) {
  const dp = 'min(max((Y-$_hzn)/(H*0.30)\\,0)\\,1)';
  const vx = '((X-W/2)/(W*0.66))';
  const vy = '((Y-H/2)/(H*0.58))';
  const vig = '(1-0.14*($vx*$vx+$vy*$vy))';
  // Broad wet sheen on the near ground: the pitch catches the rig instead of
  // being striped by it.
  const sheen = 'max(0\\,1-((X-W/2)/(W*0.66))*((X-W/2)/(W*0.66))'
      '-((Y-H*0.88)/(H*0.30))*((Y-H*0.88)/(H*0.30)))';
  // Soft luminous ceiling around the rig, so the upper frame is haze rather
  // than empty black — the atmosphere nocturne and aurora both have.
  const rigGlow = 'max(0\\,1-abs(Y-H*0.16)/(H*0.42))';

  // Light only. The rig comes up over the intro and dims over the outro; the
  // haze it is seen through also drifts, which is the whole volumetric cue.
  final lit =
      settle ? '(0.30+0.70*(1-${ease('T', 0.10, d)}))' : ease('T', 0.05, 1.60);
  final hazeCY =
      settle ? '(H*(0.34+0.10*${ease('T', 0.10, d)}))' : '(H*0.34)';

  String lampSum(int k) {
    final out = <String>[];
    for (var i = 0; i < _lampSpec.length; i++) {
      final s = _lampSpec[i];
      // The rig pans as one array, each lamp on its own phase so it never looks
      // like a single rigid bar sliding across the frame.
      final lampX = 'W*${s.$1}+W*0.035*'
          'sin(2*PI*T/${d.toStringAsFixed(2)}*0.55+${s.$7})';
      // Slot 1 = lamp x, slot 2 = where this lamp's cone lands, slot 3 = the
      // drifting haze band it is seen through.
      final foot = 'ld(1)+(H*${s.$3}-H*${s.$2})*${s.$5}';
      final haze = 'max(0\\,1-abs(Y-$hazeCY)/(H*0.46))';
      // Axis splayed by [spread]; the cone widens as it descends.
      final axis = 'ld(1)+(Y-H*${s.$2})*${s.$5}';
      final perp = 'abs(X-($axis))';
      // A cone, not a streak: the half width grows with distance below the lamp
      // so the light opens out as it falls.
      final w = '(W*${s.$4}+max(0\\,Y-H*${s.$2})*0.26)';
      final core = 'max(0\\,1-$perp/$w)';
      final halo = 'max(0\\,1-$perp/($w*2.4))';
      final env = '${c01('(Y-H*${s.$2})/(H*0.05)')}'
          '*${c01('(H*${s.$3}+H*0.03-Y)/(H*0.10)')}';
      final coneAmp = (s.$6 * _coneCol[k]).toStringAsFixed(2);
      final cone =
          '(($core*$core+$halo*$halo*$halo*0.12)*$env*ld(3)*$coneAmp)';

      // The pool the cone lands in: a wide flat ellipse, hot core inside a soft
      // skirt.
      final pw = (s.$4 * 3.6).toStringAsFixed(3);
      final ph = (s.$4 * 3.6 * 0.26).toStringAsFixed(3);
      final px = '((X-ld(2))/(W*$pw))';
      final py = '((Y-H*${s.$3})/(H*$ph))';
      final p = 'max(0\\,1-$px*$px-$py*$py)';
      final poolAmp = (_poolCol[k] * s.$6).toStringAsFixed(2);
      final pool = '$poolAmp*($p*$p+0.6*$p*$p*$p+0.45*$p)';

      // Wet ground: the pool smears straight down into a shimmering reflection.
      // This is zenith's ground signature — nocturne's mow stripes are gone.
      final rx =
          'max(0\\,1-abs(X-ld(2))/(W*${(s.$4 * 2.2).toStringAsFixed(3)}))';
      final ry = '${c01('(Y-H*${s.$3})/(H*0.02)')}'
          '*max(0\\,1-(Y-H*${s.$3})/(H*0.26))';
      final shimmer = '(0.55+0.45*sin(2*PI*T/$d*1.3+${s.$7}))';
      final reflAmp = (_reflCol[k] * s.$6).toStringAsFixed(2);
      final refl = '$reflAmp*$rx*$ry*$shimmer';

      out.add('${slot(1, lampX)}+${slot(2, foot)}+${slot(3, haze)}'
          '+$cone+$pool+$refl');
    }
    return out.join('+');
  }

  final base = <String>[];
  for (var k = 0; k < 3; k++) {
    final grad = '${_sky[k]}+${(_ground[k] - _sky[k])}.0*(Y/H)';
    final light = '${lampSum(k)}+${_sheenCol[k]}.0*$sheen*$dp'
        '+${_glowCol[k]}.0*$rigGlow';
    // Same hard ceiling as the built-in scenes: geq wraps mod 256 instead of
    // clamping, so one hot pixel — this scene sums four cones, four pools and
    // four reflections — would wrap into a band of garbage. Cap, then grain.
    base.add('min(250.0\\,max(0.0\\,($grad+$lit*($light))*$vig))'
        '+(random($k)-0.5)*4.5');
  }

  // --- Graphic layer: a scoreboard bar, not nocturne's corner brackets. ---
  const bandCY = 'H*0.46';
  const bandH = 'H*0.115';
  final bandWin = win(0.55, 1.35, d - 0.85, d);
  // The bar opens vertically from its centre line, where nocturne's plate wipes
  // open horizontally.
  final grow = c01('($bandH*${ease('T', 0.55, 1.35)}-abs(Y-$bandCY))'
      '/(H*0.02)');
  final endFade = c01('(W*0.34-abs(X-W/2))/(W*0.10)');
  final topRule = c01('${line('Y-($bandCY-$bandH)', '1.4')}'
      '*$endFade*($grow)');
  // Tick scale riding under the bar, like a scoreboard's segment strip.
  final ticks = c01('${line('mod(X+W/40\\,W/20)-W/40', '1.0')}'
      '*${c01('(H*0.014-abs(Y-($bandCY+$bandH)))/(H*0.007)')}'
      '*$endFade');

  String cap(String x) => c01('${c01('(W*0.006-abs(X-$x))/(W*0.004)')}'
      '*${c01('(H*0.10-abs(Y-$bandCY))/(H*0.05)')}');
  final caps = c01('(${cap('W*0.16')})+(${cap('W*0.84')})');
  // A plumb line up to the frame edge — the rig hangs from something.
  final plumb = c01('${c01('(W*0.0035-abs(X-W/2))/(W*0.0025)')}'
      '*${c01('(($bandCY-$bandH)-Y)/(H*0.02)')}'
      '*${c01('Y/(H*0.50)')}');

  final layers = <Layer>[
    if (withPlate)
      (c01(rect('W/2', bandCY, 'W*0.34', bandH, '16')),
          '(0.55)*($bandWin)*($grow)', _plate),
    if (withPlate) (topRule, '(0.85)*($bandWin)', _accent),
    if (withPlate) (ticks, '(0.42)*($bandWin)', _accent),
    (caps, '(0.32)*($bandWin)', _accent),
    (plumb, '(0.26)*($bandWin)', _accent),
  ];
  return (layers, base);
}

String _startup(double d) {
  final scene = _scene(d, withPlate: true);
  return clip(scene, fadeIn: 0.5, fadeOutStart: d - 0.6, fadeOut: 0.6);
}

/// No burned text and no second rule: an online ending only has to reserve the
/// area the app overlays its own line into, exactly like the startup.
String _ending(double d) {
  final scene = _scene(d, withPlate: true, settle: true);
  return clip(scene, fadeIn: 0.3, fadeOutStart: d - 0.8, fadeOut: 0.8);
}

/// Reserved centre zone for the overlay text; outside it, four narrow cones
/// sweep across at different speeds and a tick rail holds the bottom third.
String _transition(double d) {
  String cone(double phase, double w, double amp) {
    final x = '(mod(W*1.6*(T/$d+$phase)\\,W*2.4)-W*0.7)';
    final widen = '(0.55+0.45*${c01('(Y-H*0.30)/(H*0.50)')})';
    final env = c01('(H*0.86-abs(Y-H*0.46))/(H*0.44)');
    return '${line('abs(X-$x)', w.toStringAsFixed(1))}*$widen*$env*$amp';
  }

  final rail = '${line('Y-H*0.78', '1.6')}'
      '*66*${win(0.10, 0.45, 1.05, 1.35)}';

  List<String> outside(int k) => [
        cone(0.00, 30.0, _coneCol[k] * 0.42),
        cone(0.34, 22.0, _coneCol[k] * 0.32),
        cone(0.66, 15.0, _coneCol[k] * 0.22),
        cone(0.85, 10.0, _coneCol[k] * 0.15),
        rail,
      ];

  return transitionClip(
    d: d,
    outside: outside,
    ring: _ring,
    sky: _sky,
    ground: _ground,
  );
}
