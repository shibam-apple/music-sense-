import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class XmbItem {
  const XmbItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The XMB bar: a row of icons on a drifting wave band. The active icon
/// holds a fixed slot inside a soft glow, and the whole row slides with
/// [page] so the next icon glides into that slot as you swipe.
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

class _XmbBarState extends State<XmbBar> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const height = MsSizes.barHeight;
    const mid = height / 2;
    const slot = MsSizes.barSlotX;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _WavePainter(drift: _drift, page: widget.page),
              ),
            ),
          ),
          // Glow stays in the slot; icons pass through it.
          Positioned(
            left: slot - 46,
            top: mid - 50,
            width: 92,
            height: 92,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x426F56F8), Color(0x006F56F8)],
                  ),
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: widget.page,
            builder: (context, _) {
              final p = widget.page.value;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final (i, item) in widget.items.indexed)
                    if ((i - p).abs() < 7)
                      _icon(i, item, p, mid, slot),
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
    final size = ui.lerpDouble(23, 27, active)!;
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
                child: Center(child: Icon(item.icon, size: size, color: color)),
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

/// Two thin lavender waves that cross behind the icons, as on the XMB.
/// They drift slowly over time and shift with the page.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.drift, required this.page})
      : super(repaint: Listenable.merge([drift, page]));

  final Animation<double> drift;
  final Animation<double> page;

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value * math.pi * 2;
    final shift = page.value * 0.55;
    final mid = size.height / 2;

    void wave(double amplitude, double length, double phase, double offset,
        Color color, double stroke) {
      final path = Path();
      for (var x = -4.0; x <= size.width + 4; x += 4) {
        final y = mid +
            offset +
            amplitude * math.sin(x / length * math.pi * 2 + phase) +
            amplitude * 0.25 * math.sin(x / (length * 0.47) - phase * 1.7);
        x == -4 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(size.width, 0),
            [color.withValues(alpha: 0.2), color, color.withValues(alpha: 0.35)],
            const [0, 0.55, 1],
          ),
      );
    }

    wave(15, size.width * 1.3, t + shift + 2.6, 2, MsColors.wave, 1.2);
    wave(11, size.width * 1.05, -t * 0.8 - shift + 0.4, 8,
        MsColors.wave.withValues(alpha: 0.75), 1.0);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => false;
}
