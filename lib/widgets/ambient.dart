import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import 'artwork.dart';

/// Resolves the accent colour of the current song's cover and fades the
/// whole app to it when the song changes. Read with [Accent.of].
class NowPlayingAccent extends StatefulWidget {
  const NowPlayingAccent({super.key, required this.child});

  final Widget child;

  @override
  State<NowPlayingAccent> createState() => _NowPlayingAccentState();
}

class _NowPlayingAccentState extends State<NowPlayingAccent> {
  Color _target = MsColors.accentSoft;
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final track = PlayerScope.of(context).track;
    if (track == null || track.key == _key) return;
    _key = track.key;
    final art = track.artwork;
    final quick = ArtworkPalette.peek(art);
    if (quick != null) {
      _target = quick;
    } else {
      ArtworkPalette.of(art).then((c) {
        if (mounted && _key == track.key) setState(() => _target = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _target),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, color, child) =>
          Accent(color: color ?? _target, child: child!),
      child: widget.child,
    );
  }
}

class Accent extends InheritedWidget {
  const Accent({super.key, required this.color, required super.child});

  final Color color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Accent>()?.color ??
      MsColors.accentSoft;

  @override
  bool updateShouldNotify(Accent oldWidget) => oldWidget.color != color;
}

/// Calls [builder] every frame with a 0–1 pulse that peaks on each beat of
/// the playing song (and rests at 0 when paused or the beat is unknown).
class BeatPulse extends StatefulWidget {
  const BeatPulse({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, double pulse, Widget? child) builder;
  final Widget? child;

  @override
  State<BeatPulse> createState() => _BeatPulseState();
}

class _BeatPulseState extends State<BeatPulse> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _pulse = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final player = PlayerScope.read(context);
      final phase = player.playing ? player.beatPhase : null;
      final next = phase == null ? _pulse * 0.9 : math.exp(-phase * 6);
      if ((next - _pulse).abs() > 0.004) setState(() => _pulse = next);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _pulse, widget.child);
}

/// PlayStation-style ambient backdrop: soft light in the cover's colour
/// drifting slowly behind the pages, on top of the white canvas.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key});

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Accent.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientPainter(_drift, color),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.drift, this.color) : super(repaint: drift);

  final Animation<double> drift;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value * math.pi * 2;
    final w = size.width, h = size.height;
    void glow(double x, double y, double r, double alpha) {
      final c = Offset(x, y);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(w * (0.85 + 0.08 * math.sin(t)), h * (0.06 + 0.04 * math.cos(t * 2)), w * 0.75, 0.13);
    glow(w * (0.05 + 0.1 * math.cos(t)), h * (0.42 + 0.05 * math.sin(t)), w * 0.6, 0.06);
    glow(w * (0.6 + 0.1 * math.sin(t + 2)), h * (0.86 + 0.03 * math.cos(t)), w * 0.7, 0.09);
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => old.color != color;
}

/// A soft diagonal light that sweeps across its child every few seconds,
/// the way PlayStation tiles shimmer when focused.
class Glint extends StatefulWidget {
  const Glint({
    super.key,
    required this.child,
    this.radius = MsSizes.tileRadius,
    this.period = const Duration(seconds: 7),
    this.delay = Duration.zero,
  });

  final Widget child;
  final double radius;
  final Duration period;
  final Duration delay;

  @override
  State<Glint> createState() => _GlintState();
}

class _GlintState extends State<Glint> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    // Start part-way through the cycle so the first sweep comes after
    // [delay]; the sweep happens at the start of each cycle.
    final offset = widget.delay.inMicroseconds / widget.period.inMicroseconds;
    _controller.value = (1 - offset) % 1;
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // Sweep during the first 18% of each period, then rest.
                  final x = (_controller.value / 0.18).clamp(0.0, 1.0);
                  if (x <= 0 || x >= 1) return const SizedBox.shrink();
                  final at = -0.6 + 2.2 * Curves.easeInOut.transform(x);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-1, -1),
                        end: const Alignment(1, 1),
                        stops: [
                          (at - 0.18).clamp(0.0, 1.0),
                          at.clamp(0.0, 1.0),
                          (at + 0.18).clamp(0.0, 1.0),
                        ],
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.28),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small motes of light that rise off a cover in time with the music.
class LightMotes extends StatefulWidget {
  const LightMotes({super.key, required this.child});

  final Widget child;

  @override
  State<LightMotes> createState() => _LightMotesState();
}

class _Mote {
  _Mote(this.x, this.size, this.speed, this.born);
  final double x, size, speed;
  final Duration born;
}

class _LightMotesState extends State<LightMotes> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _motes = <_Mote>[];
  final _rng = math.Random(3);
  Duration _now = Duration.zero;
  double _lastPhase = 1;

  static const _life = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _now = elapsed;
      final player = PlayerScope.read(context);
      final phase = player.playing ? player.beatPhase : null;
      // A new beat started: release a few motes.
      if (phase != null && phase < _lastPhase - 0.5) {
        for (var i = 0; i < 2 + _rng.nextInt(2); i++) {
          _motes.add(_Mote(_rng.nextDouble(), 1.2 + _rng.nextDouble() * 2.2,
              0.6 + _rng.nextDouble() * 0.6, elapsed));
        }
      }
      if (phase != null) _lastPhase = phase;
      final had = _motes.isNotEmpty;
      _motes.removeWhere((m) => elapsed - m.born > _life);
      if (had || _motes.isNotEmpty) setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _MotesPainter(_motes, _now, Accent.of(context)),
      child: widget.child,
    );
  }
}

class _MotesPainter extends CustomPainter {
  _MotesPainter(this.motes, this.now, this.color);

  final List<_Mote> motes;
  final Duration now;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in motes) {
      final age = (now - m.born).inMicroseconds / _LightMotesState._life.inMicroseconds;
      final y = size.height * (0.92 - age * 0.75 * m.speed);
      final x = size.width * (0.1 + 0.8 * m.x) + math.sin(age * 6 + m.x * 9) * 8;
      final alpha = math.sin(age * math.pi) * 0.9;
      final c = Offset(x, y);
      canvas.drawCircle(c, m.size * 3,
          Paint()..color = color.withValues(alpha: alpha * 0.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(c, m.size, Paint()..color = Colors.white.withValues(alpha: alpha));
    }
  }

  @override
  bool shouldRepaint(_MotesPainter old) => true;
}

/// The three-bar "now playing" glyph, dancing with the beat while playing.
class PlayingBars extends StatelessWidget {
  const PlayingBars({super.key, this.color = MsColors.accent, this.size = 11});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final playing = PlayerScope.of(context).playing;
    return BeatPulse(
      builder: (context, pulse, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BarsPainter(playing ? pulse : 0, color)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.pulse, this.color);

  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.16
      ..strokeCap = StrokeCap.round;
    const rest = [0.45, 0.85, 0.6];
    const swing = [0.4, -0.3, 0.35];
    for (var i = 0; i < 3; i++) {
      final x = size.width * (0.18 + i * 0.32);
      final h = (rest[i] + swing[i] * pulse).clamp(0.2, 1.0) * size.height;
      canvas.drawLine(Offset(x, size.height), Offset(x, size.height - h), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.pulse != pulse || old.color != color;
}

/// Cover art with the polish used on the big covers: a beat "breath", the
/// light sweep and a shadow tinted with the cover's colour.
class LiveCover extends StatelessWidget {
  const LiveCover({super.key, required this.art, this.radius = 12, this.motes = false});

  final ArtworkRef art;
  final double radius;
  final bool motes;

  @override
  Widget build(BuildContext context) {
    final accent = Accent.of(context);
    Widget cover = Glint(
      radius: radius,
      child: Artwork(art: art, radius: radius, shadow: true, shadowColor: accent),
    );
    if (motes) cover = LightMotes(child: cover);
    return BeatPulse(
      child: cover,
      builder: (context, pulse, child) =>
          Transform.scale(scale: 1 + 0.008 * pulse, child: child),
    );
  }
}
