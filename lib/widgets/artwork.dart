import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../library/models.dart';
import '../sources/local_source.dart';
import '../theme/tokens.dart';

/// A cover: painted, from the network, or embedded in a local file.
/// Real covers fade in over their painted fallback.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.art,
    this.radius = MsSizes.tileRadius,
    this.shadow = false,
    this.shadowColor,
  });

  Artwork.painted(ArtStyle style,
      {Key? key, double radius = MsSizes.tileRadius, bool shadow = false})
      : this(key: key, art: PaintedArtwork(style), radius: radius, shadow: shadow);

  final ArtworkRef art;
  final double radius;
  final bool shadow;

  /// Tints the shadow, e.g. with the cover's accent colour.
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final image = switch (art) {
      PaintedArtwork(:final style) => _Painted(style),
      NetworkArtwork(:final url) => _Network(url),
      LocalArtwork(:final mediaId, :final fallback) => _Local(mediaId, fallback),
    };
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: RepaintBoundary(child: image),
    );
    if (!shadow) return clipped;
    final tint = shadowColor ?? MsColors.ink;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: tint.withValues(alpha: 0.20),
            blurRadius: 36,
            spreadRadius: -4,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: clipped,
    );
  }
}

class _Painted extends StatelessWidget {
  const _Painted(this.style);

  final ArtStyle style;

  @override
  Widget build(BuildContext context) {
    final painter = switch (style) {
      ArtStyle.futuristic => const _FuturisticPainter(),
      ArtStyle.lake => const _LakePainter(),
      ArtStyle.dust => const _DustPainter(),
    };
    return CustomPaint(painter: painter, child: const SizedBox.expand());
  }
}

class _Network extends StatelessWidget {
  const _Network(this.url);

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = _Painted(ArtStyle.values[url.hashCode.abs() % 3]);
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => _FadeIn(
        visible: sync || frame != null,
        fallback: fallback,
        child: child,
      ),
      errorBuilder: (context, error, stack) => fallback,
    );
  }
}

class _Local extends StatefulWidget {
  const _Local(this.mediaId, this.fallback);

  final int mediaId;
  final ArtStyle fallback;

  @override
  State<_Local> createState() => _LocalState();
}

class _LocalState extends State<_Local> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    LocalCovers.load(widget.mediaId).then((bytes) {
      if (mounted && bytes != null) setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _Painted(widget.fallback);
    final bytes = _bytes ?? LocalCovers.peek(widget.mediaId);
    if (bytes == null) return fallback;
    return _FadeIn(
      visible: true,
      fallback: fallback,
      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.visible, required this.fallback, required this.child});

  final bool visible;
  final Widget fallback;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: MsMotion.medium,
          curve: MsMotion.curve,
          child: child,
        ),
      ],
    );
  }
}

/// A small cache of local cover bytes so scrolling doesn't reload them.
abstract final class LocalCovers {
  static final _cache = <int, Uint8List?>{};
  static final _order = <int>[];
  static final _pending = <int, Future<Uint8List?>>{};
  static const _max = 120;

  static Uint8List? peek(int id) => _cache[id];

  static Future<Uint8List?> load(int id) {
    if (_cache.containsKey(id)) return Future.value(_cache[id]);
    return _pending.putIfAbsent(id, () async {
      Uint8List? bytes;
      try {
        bytes = await LocalSource.artwork(id);
      } catch (_) {}
      _cache[id] = bytes;
      _order.add(id);
      if (_order.length > _max) _cache.remove(_order.removeAt(0));
      _pending.remove(id);
      return bytes;
    });
  }
}

/// The accent colour of a cover: its most vivid colour, used to tint the
/// wave, the glow and shadows so the whole page follows the music.
abstract final class ArtworkPalette {
  static const _painted = {
    ArtStyle.futuristic: Color(0xFF8C7BFF),
    ArtStyle.lake: Color(0xFFE0956A),
    ArtStyle.dust: Color(0xFFD4893A),
  };

  static final _cache = <String, Color>{};

  static Color? peek(ArtworkRef art) => switch (art) {
        PaintedArtwork(:final style) => _painted[style],
        _ => _cache[_key(art)],
      };

  static Future<Color> of(ArtworkRef art) async {
    final known = peek(art);
    if (known != null) return known;
    Uint8List? bytes;
    ArtStyle fallback = ArtStyle.futuristic;
    try {
      switch (art) {
        case NetworkArtwork(:final url):
          final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
          bytes = data.buffer.asUint8List();
        case LocalArtwork(:final mediaId, fallback: final f):
          fallback = f;
          bytes = await LocalCovers.load(mediaId);
        case PaintedArtwork():
          break;
      }
    } catch (_) {}
    final color = bytes == null ? _painted[fallback]! : await _vivid(bytes);
    return _cache[_key(art)] = color;
  }

  static String _key(ArtworkRef art) => switch (art) {
        NetworkArtwork(:final url) => url,
        LocalArtwork(:final mediaId) => 'local:$mediaId',
        PaintedArtwork(:final style) => style.name,
      };

  /// Decodes a 24 px thumbnail and picks the most saturated mid-bright
  /// colour, weighted by how often it appears.
  static Future<Color> _vivid(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    if (data == null) return _painted[ArtStyle.futuristic]!;
    final buckets = <int, (double, double, double, double)>{};
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i) / 255, g = data.getUint8(i + 1) / 255, b = data.getUint8(i + 2) / 255;
      final hsv = HSVColor.fromColor(Color.fromARGB(255, (r * 255).round(), (g * 255).round(), (b * 255).round()));
      if (hsv.value < 0.25 || hsv.value > 0.97) continue;
      final weight = hsv.saturation * hsv.saturation;
      final bucket = (hsv.hue / 30).floor();
      final e = buckets[bucket] ?? (0, 0, 0, 0);
      buckets[bucket] = (e.$1 + r * weight, e.$2 + g * weight, e.$3 + b * weight, e.$4 + weight);
    }
    if (buckets.isEmpty) return const Color(0xFF8C7BFF);
    final best = buckets.values.reduce((a, b) => a.$4 >= b.$4 ? a : b);
    if (best.$4 < 0.5) return const Color(0xFF8C7BFF);
    final c = Color.fromARGB(255, (best.$1 / best.$4 * 255).round(), (best.$2 / best.$4 * 255).round(),
        (best.$3 / best.$4 * 255).round());
    // Keep it bright enough to read as a glow on white.
    final hsv = HSVColor.fromColor(c);
    return hsv.withValue(math.max(hsv.value, 0.7)).withSaturation(math.max(hsv.saturation, 0.45)).toColor();
  }
}

/// "futuristic" — black sleeve, iridescent ring, tilted wordmark.
class _FuturisticPainter extends CustomPainter {
  const _FuturisticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF111113));

    final c = Offset(w * 0.5, h * 0.49);
    final ring = _wobblyRing(c, w * 0.27, h * 0.17);
    final iridescent = SweepGradient(
      center: Alignment.center,
      colors: const [
        Color(0xFF7FE7FF),
        Color(0xFFE38BFF),
        Color(0xFFFFD27A),
        Color(0xFFFFFFFF),
        Color(0xFF6E8BFF),
        Color(0xFF7FE7FF),
      ],
    ).createShader(Rect.fromCircle(center: c, radius: w * 0.3));

    // Soft glow, then the crisp ring, then a thin inner echo.
    canvas.drawPath(
      ring,
      Paint()
        ..shader = iridescent
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
    );
    canvas.drawPath(
      ring,
      Paint()
        ..shader = iridescent
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.014,
    );
    canvas.drawPath(
      _wobblyRing(c.translate(w * 0.01, h * 0.012), w * 0.24, h * 0.145,
          phase: 1.3),
      Paint()
        ..shader = iridescent
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.005
        ..color = Colors.white.withValues(alpha: 0.6),
    );

    // Wordmark.
    canvas.save();
    canvas.translate(c.dx, c.dy + h * 0.01);
    canvas.rotate(-0.1);
    _text(
      canvas,
      'futuristic',
      Offset.zero,
      TextStyle(
        fontFamily: MsText.family,
        fontSize: w * 0.155,
        fontWeight: FontWeight.w700,
        letterSpacing: -w * 0.006,
        color: Colors.white,
      ),
    );
    canvas.restore();

    // Sparkle rules either side.
    final rule = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = math.max(0.6, w * 0.004);
    for (final side in [-1.0, 1.0]) {
      final inner = Offset(w * 0.5 + side * w * 0.35, c.dy);
      canvas.drawLine(inner, inner.translate(side * w * 0.07, 0), rule);
      _sparkle(canvas, inner, w * 0.018);
    }

    final tiny = TextStyle(
      fontFamily: MsText.family,
      fontSize: math.max(3, w * 0.024),
      fontWeight: FontWeight.w500,
      letterSpacing: w * 0.004,
      color: Colors.white.withValues(alpha: 0.75),
    );
    _text(canvas, 'VOL. 01', Offset(w * 0.5, h * 0.15), tiny);
    _text(canvas, 'RUFUS STEWART', Offset(w * 0.5, h * 0.86), tiny);
  }

  Path _wobblyRing(Offset c, double rx, double ry, {double phase = 0}) {
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * math.pi * 2;
      final wobble = 1 +
          0.09 * math.sin(3 * t + phase) +
          0.05 * math.cos(5 * t + phase * 2);
      final p = Offset(
        c.dx + rx * wobble * math.cos(t),
        c.dy + ry * wobble * math.sin(t) - ry * 0.12 * math.cos(2 * t),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  void _sparkle(Canvas canvas, Offset c, double r) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "lake" — sunset over a fjord, mirrored in still water.
class _LakePainter extends CustomPainter {
  const _LakePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.58;

    void sky(Canvas canvas) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, horizon),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, horizon),
            const [
              Color(0xFF26304E),
              Color(0xFF5B5674),
              Color(0xFFC98A72),
              Color(0xFFF6C38C),
            ],
            const [0, 0.4, 0.78, 1],
          ),
      );
      final sun = Offset(w * 0.55, horizon * 0.86);
      canvas.drawCircle(
        sun,
        w * 0.45,
        Paint()
          ..shader = ui.Gradient.radial(
              sun, w * 0.45, [const Color(0xB3FFD39A), const Color(0x00FFD39A)]),
      );
      // Clouds: dark bodies with warm undersides.
      for (final (x, y, rw, rh) in const [
        (0.18, 0.1, 0.5, 0.07),
        (0.72, 0.14, 0.55, 0.08),
        (0.42, 0.26, 0.42, 0.045),
        (0.9, 0.3, 0.3, 0.04),
      ]) {
        final rect = Rect.fromCenter(
            center: Offset(w * x, h * y), width: w * rw, height: h * rh);
        canvas.drawOval(
          rect,
          Paint()
            ..color = const Color(0x66272033)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.025),
        );
        canvas.drawOval(
          rect.shift(Offset(0, h * 0.012)).deflate(w * 0.03),
          Paint()
            ..color = const Color(0x55FFB27A)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
        );
      }
    }

    // Far range: peaks either side of a low valley, snow on the tops.
    final far = _ridge(w, horizon, seed: 3, roughness: 0.07,
        profile: (x) => 0.36 + 0.3 * math.pow((x - 0.55).abs() * 2, 1.4));
    // Near cliffs: steep on both sides, open to the water in the middle.
    final near = _ridge(w, horizon, seed: 11, roughness: 0.05,
        profile: (x) => 0.04 + 0.86 * math.pow((x - 0.52).abs() * 2, 2.2));

    void ridges(Canvas canvas) {
      canvas.drawPath(
        far,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, horizon * 0.25),
            Offset(0, horizon),
            const [Color(0xFF9CA3BA), Color(0xFF59607A), Color(0xFF3A405A)],
            const [0, 0.35, 1],
          ),
      );
      canvas.drawPath(
        near,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, horizon * 0.15),
            Offset(0, horizon),
            const [Color(0xFF2E3550), Color(0xFF151A27)],
          ),
      );
    }

    sky(canvas);
    ridges(canvas);

    // Water: the scene mirrored, softened and darkened toward the viewer.
    final water = Rect.fromLTWH(0, horizon, w, h - horizon);
    canvas.save();
    canvas.clipRect(water);
    canvas.saveLayer(
      water,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: w * 0.004, sigmaY: h * 0.01),
    );
    canvas.translate(0, horizon * 2);
    canvas.scale(1, -1);
    sky(canvas);
    ridges(canvas);
    canvas.restore();
    canvas.drawRect(
      water,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, horizon),
          Offset(0, h),
          const [Color(0x22080A12), Color(0xCC080A12)],
        ),
    );
    final shimmer = Paint()
      ..color = const Color(0x33FFE0B8)
      ..strokeWidth = math.max(0.4, h * 0.003);
    final rng = math.Random(5);
    for (var i = 0; i < 14; i++) {
      final y = horizon + (h - horizon) * (0.04 + i * 0.065);
      final half = w * (0.04 + rng.nextDouble() * 0.12);
      final cx = w * (0.48 + rng.nextDouble() * 0.12);
      canvas.drawLine(Offset(cx - half, y), Offset(cx + half, y), shimmer);
    }
    canvas.restore();
  }

  /// A ridge line from [profile] (height above the horizon as a fraction of
  /// it) plus a few octaves of seeded noise, so peaks look natural.
  Path _ridge(double w, double horizon,
      {required int seed,
      required double roughness,
      required double Function(double x) profile}) {
    final rng = math.Random(seed);
    final phases = List.generate(4, (_) => rng.nextDouble() * math.pi * 2);
    final path = Path()..moveTo(0, horizon);
    const steps = 90;
    for (var i = 0; i <= steps; i++) {
      final x = i / steps;
      var noise = 0.0;
      for (var o = 0; o < 4; o++) {
        final f = math.pow(2.3, o) * 4;
        noise += math.sin(x * f + phases[o]).abs() / math.pow(1.9, o);
      }
      final height = (profile(x) + roughness * (noise - 1)).clamp(0.0, 0.95);
      path.lineTo(w * x, horizon * (1 - height));
    }
    return path
      ..lineTo(w, horizon)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "dust" — a plume of desert sand thrown up and lit by low sun.
class _DustPainter extends CustomPainter {
  const _DustPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          const [Color(0xFF8F9195), Color(0xFFC4B29A), Color(0xFFDDA35E)],
          const [0, 0.55, 1],
        ),
    );

    // The plume leaves a point low on the right and fans up to the left.
    final source = Offset(w * 0.8, h * 0.92);
    final rng = math.Random(7);
    Offset along(double distance, double angle) =>
        source + Offset(math.cos(angle), math.sin(angle)) * distance;
    double coneAngle() => math.pi * (1.08 + rng.nextDouble() * 0.32);

    for (var i = 0; i < 46; i++) {
      final d = w * (0.05 + math.pow(rng.nextDouble(), 0.8) * 0.85);
      final r = w * (0.06 + d / w * 0.2) * (0.6 + rng.nextDouble() * 0.6);
      final warm = Color.lerp(const Color(0xFFB8682A), const Color(0xFFF0C07E),
          rng.nextDouble())!;
      canvas.drawCircle(
        along(d, coneAngle()),
        r,
        Paint()
          ..color = warm.withValues(alpha: 0.18 + rng.nextDouble() * 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.55),
      );
    }

    final grit = Paint();
    for (var i = 0; i < 1100; i++) {
      final d = w * math.pow(rng.nextDouble(), 0.7) * 0.95;
      final p = along(d, coneAngle());
      grit.color = const Color(0xFF4E2C12)
          .withValues(alpha: 0.35 + rng.nextDouble() * 0.55);
      canvas.drawCircle(p, w * (0.001 + rng.nextDouble() * 0.0028), grit);
    }

    // Sunlit dune in the foreground.
    final dune = Path()
      ..moveTo(0, h * 0.93)
      ..quadraticBezierTo(w * 0.55, h * 0.84, w, h * 0.9)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      dune,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, h * 0.85), Offset(0, h),
            const [Color(0xFFC77D36), Color(0xFF8E4F1E)]),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _text(Canvas canvas, String text, Offset centre, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
}
