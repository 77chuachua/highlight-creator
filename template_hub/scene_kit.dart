// Shared primitives for the online template sets' generators.
//
// The graphs these emit are the same language the built-in scenes are written in
// (app/lib/data/ffi/video_processing_service.dart): `geq` with `st()`/`ld()`
// slots, smoothstep easing, hairlines as `1-|v|/th`. Keeping them in one file is
// what lets two sets share the *materials* — grain, haze, easing, the layer fold
// — while their scenes and graphic furniture stay independent, which is exactly
// the brief: same texture, clearly different forms.
//
// Escaping note: the graph is a comma-separated filter chain, so a comma inside
// a `geq` argument is written `\,` — every helper emits `\\,` in Dart source.
//
// Run the set generators from template_hub/:  dart gen_aurora.dart

/// One graphic layer: (mask, alpha, [r, g, b]).
typedef Layer = (String, String, List<String>);

/// A (layers, base) scene: the per-channel pixel expression before the graphic
/// fold, plus the hairline layers folded over it. The same contract the built-in
/// `_nocturneLayers` uses.
typedef Scene = (List<Layer>, List<String>);

/// `min(max((T-a)/(b-a),0),1)` — the linear time ramp every window is built on.
String ramp(double a, double b) {
  final w = (b - a).toStringAsFixed(3);
  return 'min(max((T-$a)/$w\\,0)\\,1)';
}

/// Smoothstep between [t0] and [t1] on the geq clock [t].
///
/// A linear ramp reads crude: real light comes up fast and then settles.
String ease(String t, double t0, double t1) {
  final w = (t1 - t0).toStringAsFixed(3);
  final u = 'min(max(($t-$t0)/$w\\,0)\\,1)';
  return '($u)*($u)*(3.0-2.0*($u))';
}

/// A window that ramps in over [si]..[ei] and out over [so]..[eo].
String win(double si, double ei, double so, double eo) =>
    'min(${ramp(si, ei)}\\,(1-${ramp(so, eo)}))';

/// Hairline of thickness [th] around [v] = 0.
///
/// [th] is a string so a caller can make it grow with depth (a cone that widens
/// downward) instead of baking a constant.
String line(String v, String th) => 'max(0\\,1-abs($v)/$th)';

/// Clamp to 0..1.
String c01(String e) => 'min(max($e\\,0)\\,1)';

/// Evaluate [expr] into geq slot [slot] and contribute nothing to the value.
///
/// geq has no statement form, so the store rides along the surrounding sum
/// multiplied by zero. Slots 0-3 are the light rig, 4+ the graphic layers.
String slot(int index, String expr) => '(st($index,$expr)*0)';

/// Soft-edged rectangle: (centre, half extents, edge softness).
String rect(String cx, String cy, String hw, String hh, String s) =>
    '(${c01('(($hw)-abs(X-($cx)))/$s')})*'
    '(${c01('(($hh)-abs(Y-($cy)))/$s')})';

/// Layer fold: `acc*(1-a)+color*a` per channel, with every alpha evaluated once
/// into its own geq slot and read back twice.
///
/// That halving is the difference between fitting Windows' 32767-character
/// command line and failing to launch ffmpeg at all.
String foldLayers(List<Layer> layers, List<String> base) {
  String channel(int k) {
    var acc = base[k];
    final stores = <String>[];
    for (var i = 0; i < layers.length; i++) {
      stores.add(slot(4 + i, '(${layers[i].$1})*(${layers[i].$2})'));
      acc = '($acc)*(1-ld(${4 + i}))+(${layers[i].$3[k]})*ld(${4 + i})';
    }
    return '${stores.join('+')}+($acc)';
  }

  return "geq=r='${channel(0)}':g='${channel(1)}':b='${channel(2)}'";
}

/// A full clip graph: half-resolution rgb24 scene, scaled up, 30 fps, faded.
///
/// The plugin renderer feeds a 640x360 black source and scales inside the graph,
/// which is the same trick the built-in sets use: `geq` at full resolution is
/// ~4x the work for a difference nobody sees on a soft gradient.
String clip(
  Scene scene, {
  required double fadeIn,
  required double fadeOutStart,
  required double fadeOut,
}) =>
    'format=rgb24,${foldLayers(scene.$1, scene.$2)},format=yuv420p,'
    'scale=1280:720:flags=lanczos,fps=30,'
    'fade=t=in:st=0:d=$fadeIn,fade=t=out:st=$fadeOutStart:d=$fadeOut';

/// A wipe clip with the reserved centre text zone the built-in transitions use.
///
/// The zone is centred on the frame, which is where the app overlays a
/// transition's text (`VideoProcessingService.textYExpr`); [outside] supplies
/// the per-channel light terms that animate outside it — they are summed, so a
/// caller returns them as separate terms rather than one pre-joined string —
/// and the zone's own card is darkened with a slow breathing glow so centred
/// text stays readable.
String transitionClip({
  required double d,
  required List<String> Function(int channel) outside,
  required List<String> ring,
  required List<int> sky,
  required List<int> ground,
}) {
  const zoneIn = 'lt(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))\\,1)';
  const zoneRing =
      'lt(abs(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))-1)\\,0.018)';

  String channel(int k) {
    final dark = '${sky[k]}+${(ground[k] - sky[k])}.0*0.35';
    final zone = '$dark*0.5+4+4*sin(2*PI*T/$d)';
    return 'if($zoneIn\\,$zone\\,'
        'if($zoneRing\\,${ring[k]}\\,$dark+${outside(k).join('+')}))';
  }

  return "format=rgb24,geq=r='${channel(0)}':g='${channel(1)}':b='${channel(2)}',"
      'format=yuv420p,scale=1280:720:flags=lanczos,fps=30,'
      'fade=t=in:st=0:d=0.15,fade=t=out:st=${d - 0.2}:d=0.2';
}
