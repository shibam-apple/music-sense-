import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  (Color, Color) _target = (MsColors.accentSoft, MsColors.wave);
  String? _key;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final track = PlayerScope.of(context).track;
    if (track == null || track.key == _key) return;
    _key = track.key;
    final art = track.artwork;
    final quick = ArtworkPalette.peekScheme(art);
    if (quick != null) {
      _target = quick;
    } else {
      ArtworkPalette.schemeOf(art).then((c) {
        if (mounted && _key == track.key) setState(() => _target = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_target),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, t, child) {
        final from = _from ?? _target;
        final scheme = (
          Color.lerp(from.$1, _target.$1, t)!,
          Color.lerp(from.$2, _target.$2, t)!,
        );
        if (t >= 1) _from = _target;
        _current = scheme;
        return Accent(color: scheme.$1, secondary: scheme.$2, child: child!);
      },
      child: widget.child,
    );
  }

  (Color, Color)? _from;
  (Color, Color)? _current;

  @override
  void setState(VoidCallback fn) {
    // Start the next fade from wherever the last one had got to.
    _from = _current ?? _from;
    super.setState(fn);
  }
}

class Accent extends InheritedWidget {
  const Accent({
    super.key,
    required this.color,
    required this.secondary,
    required super.child,
  });

  /// The cover's most vivid colour.
  final Color color;

  /// A second hue from the cover.
  final Color secondary;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Accent>()?.color ??
      MsColors.accentSoft;

  static (Color, Color) schemeOf(BuildContext context) {
    final a = context.dependOnInheritedWidgetOfExactType<Accent>();
    return a == null
        ? (MsColors.accentSoft, MsColors.wave)
        : (a.color, a.secondary);
  }

  @override
  bool updateShouldNotify(Accent oldWidget) =>
      oldWidget.color != color || oldWidget.secondary != secondary;
}

/// The light wash the Now Playing page takes from the cover: soft enough
/// that dark type stays crisp, strong enough to read as the album's colour.
({Color top, Color bottom}) albumWash((Color, Color) scheme) => (
  top: Color.lerp(MsColors.background, scheme.$1, 0.34)!,
  bottom: Color.lerp(MsColors.background, scheme.$2, 0.22)!,
);

/// The Now Playing background: the album's colours as slow-moving light,
/// like Apple Music's player, painted once and moved by transforms.
class AlbumBackground extends StatefulWidget {
  const AlbumBackground({super.key});

  @override
  State<AlbumBackground> createState() => _AlbumBackgroundState();
}

class _AlbumBackgroundState extends State<AlbumBackground>
    with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Accent.schemeOf(context);
    final wash = albumWash(scheme);
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, size) {
          final w = size.maxWidth, h = size.maxHeight;
          Widget blob(
            Color c,
            double alpha,
            double r,
            Offset Function(double t) at,
          ) {
            final dot = RepaintBoundary(
              child: SizedBox.square(
                dimension: r * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        c.withValues(alpha: alpha),
                        c.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return AnimatedBuilder(
              animation: _drift,
              child: dot,
              builder: (context, child) {
                final p = at(_drift.value * math.pi * 2);
                return Transform.translate(
                  offset: Offset(p.dx - r, p.dy - r),
                  child: child,
                );
              },
            );
          }

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [wash.top, wash.bottom],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: blob(
                  scheme.$1,
                  0.42,
                  w * 0.8,
                  (t) => Offset(
                    w * (0.75 + 0.12 * math.sin(t)),
                    h * (0.18 + 0.06 * math.cos(t)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: blob(
                  scheme.$2,
                  0.36,
                  w * 0.75,
                  (t) => Offset(
                    w * (0.1 + 0.12 * math.cos(t + 1)),
                    h * (0.5 + 0.08 * math.sin(t)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: blob(
                  scheme.$1,
                  0.22,
                  w * 0.6,
                  (t) => Offset(
                    w * (0.6 + 0.1 * math.sin(t + 3)),
                    h * (0.85 + 0.04 * math.cos(t)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A cover standing on glass, as in Cover Flow: below it, a soft mirrored
/// reflection that fades out, with a faint highlight at the edge.
class ReflectedCover extends StatelessWidget {
  const ReflectedCover({
    super.key,
    required this.art,
    required this.size,
    this.radius = 14,
    this.reflection = 0.34,
    this.motes = false,
  });

  final ArtworkRef art;
  final double size;
  final double radius;

  /// Height of the reflection as a fraction of the cover.
  final double reflection;
  final bool motes;

  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final reflected = RepaintBoundary(
      child: IgnorePointer(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 1.4, sigmaY: 2.2),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000)],
            ).createShader(rect),
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: reflection,
                child: Transform.flip(
                  flipY: true,
                  child: SizedBox.square(
                    dimension: size,
                    child: Artwork(art: art, radius: radius),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size * (1 + reflection) + gap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(top: size + gap, left: 0, width: size, child: reflected),
          // Glass edge: a hairline of light where cover meets reflection.
          Positioned(
            top: size + gap - 0.5,
            left: radius,
            right: radius,
            height: 1,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x99FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: size,
            height: size,
            child: LiveCover(
              art: art,
              radius: radius,
              motes: motes,
              shadow: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// One clock for everything that moves with the music: a 0–1 pulse that
/// peaks on each beat of the playing song. Its ticker runs only while
/// music plays (and while the last pulse fades), so an idle app draws
/// nothing per frame.
class BeatClock extends StatefulWidget {
  const BeatClock({super.key, required this.child});

  final Widget child;

  /// The shared pulse; listen to it rather than rebuilding on it.
  static ValueListenable<double> of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_BeatScope>()?.pulse ?? _resting;

  static final _resting = ValueNotifier<double>(0);

  @override
  State<BeatClock> createState() => _BeatClockState();
}

class _BeatScope extends InheritedWidget {
  const _BeatScope({required this.pulse, required super.child});

  final ValueNotifier<double> pulse;

  @override
  bool updateShouldNotify(_BeatScope oldWidget) => false;
}

class _BeatClockState extends State<BeatClock>
    with SingleTickerProviderStateMixin {
  final _pulse = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker(_tick);
  PlaybackController? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = PlayerScope.of(context);
    if (player != _player) {
      _player?.removeListener(_wake);
      _player = player..addListener(_wake);
    }
    _wake();
  }

  void _wake() {
    if ((_player?.playing ?? false) && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration _) {
    final player = _player;
    final phase = player != null && player.playing ? player.beatPhase : null;
    final next = phase == null ? _pulse.value * 0.88 : math.exp(-phase * 6);
    if ((next - _pulse.value).abs() > 0.003) _pulse.value = next;
    if (phase == null && _pulse.value < 0.01) {
      _pulse.value = 0;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _player?.removeListener(_wake);
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _BeatScope(pulse: _pulse, child: widget.child);
}

/// Rebuilds only [builder]'s subtree with the shared beat pulse.
class BeatPulse extends StatelessWidget {
  const BeatPulse({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, double pulse, Widget? child)
  builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: BeatClock.of(context),
    builder: builder,
    child: child,
  );
}

/// PlayStation-style ambient backdrop: soft light in the cover's colour
/// drifting slowly behind the pages, on top of the white canvas.
///
/// Each glow is painted once and only moved by a transform as it drifts,
/// so the animation costs the GPU almost nothing per frame.
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
      child: LayoutBuilder(
        builder: (context, size) {
          final w = size.maxWidth, h = size.maxHeight;
          Widget glow(
            double radius,
            double alpha,
            Offset Function(double t) at,
          ) {
            final dot = RepaintBoundary(
              child: SizedBox.square(
                dimension: radius * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: alpha),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return AnimatedBuilder(
              animation: _drift,
              child: dot,
              builder: (context, child) {
                final c = at(_drift.value * math.pi * 2);
                return Transform.translate(
                  offset: Offset(c.dx - radius, c.dy - radius),
                  child: child,
                );
              },
            );
          }

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: glow(
                  w * 0.75,
                  0.13,
                  (t) => Offset(
                    w * (0.85 + 0.08 * math.sin(t)),
                    h * (0.06 + 0.04 * math.cos(t * 2)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: glow(
                  w * 0.6,
                  0.06,
                  (t) => Offset(
                    w * (0.05 + 0.1 * math.cos(t)),
                    h * (0.42 + 0.05 * math.sin(t)),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: glow(
                  w * 0.7,
                  0.09,
                  (t) => Offset(
                    w * (0.6 + 0.1 * math.sin(t + 2)),
                    h * (0.86 + 0.03 * math.cos(t)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A soft diagonal light that sweeps across its child every few seconds,
/// the way PlayStation tiles shimmer when focused. Animates only during
/// the sweep; a timer waits in between.
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
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      _run();
      _timer = Timer.periodic(widget.period, (_) => _run());
    });
  }

  void _run() {
    if (mounted && TickerMode.valuesOf(context).enabled) {
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GlintPainter(_sweep, widget.radius),
      child: widget.child,
    );
  }
}

class _GlintPainter extends CustomPainter {
  _GlintPainter(this.sweep, this.radius) : super(repaint: sweep);

  final Animation<double> sweep;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final x = sweep.value;
    if (x <= 0 || x >= 1) return;
    final at = -0.6 + 2.2 * Curves.easeInOut.transform(x);
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
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
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlintPainter old) => false;
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

class _LightMotesState extends State<LightMotes>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _motes = <_Mote>[];
  final _rng = math.Random(3);
  final _frame = ValueNotifier<Duration>(Duration.zero);
  double _lastPhase = 1;
  PlaybackController? _player;

  static const _life = Duration(milliseconds: 2600);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final player = PlayerScope.of(context);
    if (player != _player) {
      _player?.removeListener(_wake);
      _player = player..addListener(_wake);
    }
    _wake();
  }

  void _wake() {
    if ((_player?.playing ?? false) && !_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    final player = _player!;
    final phase = player.playing ? player.beatPhase : null;
    // A new beat started: release a few motes.
    if (phase != null && phase < _lastPhase - 0.5) {
      for (var i = 0; i < 2 + _rng.nextInt(2); i++) {
        _motes.add(
          _Mote(
            _rng.nextDouble(),
            1.2 + _rng.nextDouble() * 2.2,
            0.6 + _rng.nextDouble() * 0.6,
            elapsed,
          ),
        );
      }
    }
    if (phase != null) _lastPhase = phase;
    _motes.removeWhere((m) => elapsed - m.born > _life);
    _frame.value = elapsed;
    if (_motes.isEmpty && !player.playing) _ticker.stop();
  }

  @override
  void dispose() {
    _player?.removeListener(_wake);
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _MotesPainter(_motes, _frame, Accent.of(context)),
      child: widget.child,
    );
  }
}

class _MotesPainter extends CustomPainter {
  _MotesPainter(this.motes, this.frame, this.color) : super(repaint: frame);

  final List<_Mote> motes;
  final ValueListenable<Duration> frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in motes) {
      final age =
          (frame.value - m.born).inMicroseconds /
          _LightMotesState._life.inMicroseconds;
      final y = size.height * (0.92 - age * 0.75 * m.speed);
      final x =
          size.width * (0.1 + 0.8 * m.x) + math.sin(age * 6 + m.x * 9) * 8;
      final alpha = math.sin(age * math.pi) * 0.9;
      final c = Offset(x, y);
      final r = m.size * 4;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha * 0.3),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
      canvas.drawCircle(
        c,
        m.size,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_MotesPainter old) => old.color != color;
}

/// The three-bar "now playing" glyph, dancing with the beat while playing.
class PlayingBars extends StatelessWidget {
  const PlayingBars({super.key, this.color = MsColors.accent, this.size = 11});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BarsPainter(BeatClock.of(context), color)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.pulse, this.color) : super(repaint: pulse);

  final ValueListenable<double> pulse;
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
      final h =
          (rest[i] + swing[i] * pulse.value).clamp(0.2, 1.0) * size.height;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - h),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.color != color || old.pulse != pulse;
}

/// Cover art with the polish used on the big covers: a beat "breath", the
/// light sweep and a shadow tinted with the cover's colour.
class LiveCover extends StatelessWidget {
  const LiveCover({
    super.key,
    required this.art,
    this.radius = 12,
    this.motes = false,
    this.shadow = true,
  });

  final ArtworkRef art;
  final double radius;
  final bool motes;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final accent = Accent.of(context);
    Widget cover = Glint(
      radius: radius,
      child: Artwork(
        art: art,
        radius: radius,
        shadow: shadow,
        shadowColor: accent,
      ),
    );
    if (motes) cover = LightMotes(child: cover);
    return BeatPulse(
      child: cover,
      builder: (context, pulse, child) =>
          Transform.scale(scale: 1 + 0.008 * pulse, child: child),
    );
  }
}
