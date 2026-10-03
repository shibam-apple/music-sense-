import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ambient.dart';

class XmbItem {
  const XmbItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The XMB bar: a row of icons on a drifting wave band. The active icon
/// holds a fixed slot inside a soft glow, and the whole row slides with
/// [page] so the next icon glides into that slot as you swipe.
///
/// Per-frame work is paint-only: the waves, sparkles and glow repaint from
/// listenables; widgets rebuild only while the row is moving.
class XmbBar extends StatefulWidget {
  const XmbBar({
    super.key,
    required this.items,
    required this.page,
    required this.onSelect,
  });

  final List<XmbItem> items;

  /// Fractional page position, shared with the panorama.
  final Animation<double> page;
  final ValueChanged<int> onSelect;

  @override
  State<XmbBar> createState() => _XmbBarState();
}

class _XmbBarState extends State<XmbBar> with TickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  /// A small spring each time a new icon lands in the slot.
  late final _land = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  int _landed = 0;

  @override
  void initState() {
    super.initState();
    widget.page.addListener(_watchLanding);
  }

  void _watchLanding() {
    final p = widget.page.value;
    final nearest = p.round();
    if (nearest != _landed && (p - nearest).abs() < 0.06) {
      _landed = nearest;
      _land.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.page.removeListener(_watchLanding);
    _drift.dispose();
    _land.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = MsSizes.barHeight;
    const mid = height / 2;
    const slot = MsSizes.barSlotX;
    final accent = Accent.of(context);
    final pulse = BeatClock.of(context);

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WavePainter(
                    drift: _drift,
                    page: widget.page,
                    pulse: pulse,
                    color: Color.lerp(MsColors.wave, accent, 0.35)!,
                  ),
                ),
              ),
            ),
          ),
          // Glow stays in the slot; icons pass through it.
          Positioned(
            left: slot - 48,
            top: mid - 52,
            width: 96,
            height: 96,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _GlowPainter(
                    pulse,
                    Color.lerp(MsColors.accent, accent, 0.4)!,
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([widget.page, _land]),
            builder: (context, _) {
              final p = widget.page.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (i, item) in widget.items.indexed)
                    if ((i - p).abs() < 7) _icon(i, item, p, mid, slot),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _icon(int i, XmbItem item, double p, double mid, double slot) {
    final distance = (i - p).abs();
    final active = (1 - distance).clamp(0.0, 1.0);
    final x = slot + (i - p) * MsSizes.barSpacing;
    // Spring overshoot on the icon that just landed.
    final bounce = i == _landed && _land.isAnimating
        ? math.sin(_land.value * math.pi) * (1 - _land.value) * 0.22
        : 0.0;
    final size = ui.lerpDouble(23, 27, active)! * (1 + bounce);
    final color = Color.lerp(MsColors.iconIdle, MsColors.ink, active)!;

    return Positioned(
      left: x - 32,
      top: mid - 22,
      width: 64,
      height: 72,
      child: Semantics(
        button: true,
        selected: active > 0.5,
        label: item.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelect(i),
          child: Column(
            children: [
              SizedBox(
                height: 28,
                child: Center(
                  child: Icon(item.icon, size: size, color: color),
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: Curves.easeIn.transform(active),
                child: Text(item.label, style: MsText.barLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.pulse, this.color) : super(repaint: pulse);

  final ValueListenable<double> pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pulse.value;
    final c = size.center(Offset.zero);
    final r = size.width / 2 * (1 + 0.06 * p);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, r, [
          color.withValues(alpha: 0.24 + 0.08 * p),
          color.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.color != color || old.pulse != pulse;
}

/// Two thin waves that cross behind the icons, as on the XMB, with
/// sparkles gliding along them. They drift over time, shift with the page
/// and swell on the beat.
class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.drift,
    required this.page,
    required this.pulse,
    required this.color,
  }) : super(repaint: Listenable.merge([drift, page, pulse]));

  final Animation<double> drift;
  final Animation<double> page;
  final ValueListenable<double> pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value * math.pi * 2;
    final shift = page.value * 0.55;
    final mid = size.height / 2;
    final beat = pulse.value;
    final swell = 1 + 0.18 * beat;

    double y(
      double x,
      double amplitude,
      double length,
      double phase,
      double offset,
    ) =>
        mid +
        offset +
        swell * amplitude * math.sin(x / length * math.pi * 2 + phase) +
        swell * amplitude * 0.25 * math.sin(x / (length * 0.47) - phase * 1.7);

    final shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),
      [color.withValues(alpha: 0.2), color, color.withValues(alpha: 0.35)],
      const [0, 0.55, 1],
    );

    void wave(
      double amplitude,
      double length,
      double phase,
      double offset,
      double opacity,
      double stroke,
    ) {
      final path = Path();
      for (var x = -6.0; x <= size.width + 6; x += 6) {
        final py = y(x, amplitude, length, phase, offset);
        x == -6 ? path.moveTo(x, py) : path.lineTo(x, py);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = Color.fromRGBO(0, 0, 0, opacity)
          ..shader = shader,
      );
    }

    final a = (15.0, size.width * 1.3, t + shift + 2.6, 2.0);
    final b = (11.0, size.width * 1.05, -t * 0.8 - shift + 0.4, 8.0);
    wave(a.$1, a.$2, a.$3, a.$4, 1, 1.2);
    wave(b.$1, b.$2, b.$3, b.$4, 0.75, 1.0);

    // PS3-style sparkles gliding along the first wave. Gradient halos are
    // far cheaper per frame than blur filters.
    for (var i = 0; i < 5; i++) {
      final along = (drift.value * (1.6 + i * 0.37) + i * 0.21) % 1.0;
      final x = along * size.width;
      final c = Offset(x, y(x, a.$1, a.$2, a.$3, a.$4));
      final twinkle = 0.5 + 0.5 * math.sin(t * 7 + i * 2.1);
      final r = 1.1 + 0.9 * twinkle + 1.2 * beat;
      canvas.drawCircle(
        c,
        r * 4,
        Paint()
          ..shader = ui.Gradient.radial(c, r * 4, [
            color.withValues(alpha: 0.22 * twinkle),
            color.withValues(alpha: 0),
          ]),
      );
      canvas.drawCircle(
        c,
        r * 0.7,
        Paint()..color = Colors.white.withValues(alpha: 0.9 * twinkle),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.color != color || old.pulse != pulse || old.page != page;
}
