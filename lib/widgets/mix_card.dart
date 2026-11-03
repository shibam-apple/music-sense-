import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../beat_sense/analysis/track_analysis.dart';
import '../beat_sense/transition.dart';
import '../library/models.dart';
import '../playback/playback_controller.dart';
import '../theme/tokens.dart';
import 'ambient.dart';
import 'artwork.dart';
import 'tiles.dart';

/// Shows what Beat Sense is doing: the two songs' tempo and key, how it
/// will blend them, a countdown to the mix, and the blend as it happens.
class MixCard extends StatelessWidget {
  const MixCard({super.key});

  static String styleName(TransitionStyle s) => switch (s) {
    TransitionStyle.bassSwap => 'Bass swap',
    TransitionStyle.blend => 'Blend',
    TransitionStyle.cutOnBeat => 'Cut on the beat',
    TransitionStyle.crossfade => 'Crossfade',
    TransitionStyle.dropCut => 'Cut to the drop',
  };

  static String styleHow(TransitionStyle s) => switch (s) {
    TransitionStyle.bassSwap =>
      'Beats locked together; the bass line hands over on a downbeat so '
          'the kicks never clash.',
    TransitionStyle.blend =>
      'Keys and energy match, so both songs play together in time.',
    TransitionStyle.cutOnBeat =>
      'Tempos are too far apart to match, so the next song lands on a '
          'downbeat.',
    TransitionStyle.crossfade =>
      'No steady beat to lock to, so it fades smoothly.',
    TransitionStyle.dropCut =>
      'The song plays to the end of a phrase, and the next one\'s drop '
          'hits right on that beat.',
  };

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final status = player.beatSense;
    final current = player.track;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: MsColors.tileDark,
        borderRadius: BorderRadius.circular(MsSizes.tileRadius + 4),
      ),
      child: AnimatedSize(
        duration: MsMotion.medium,
        curve: MsMotion.emphasized,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (status.state != BeatSenseState.off) ...[
              const _DjSwitch(),
              const SizedBox(height: 14),
            ],
            _body(context, player, status, current),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PlaybackController player,
    BeatSenseStatus status,
    Track? current,
  ) {
    return switch (status.state) {
      BeatSenseState.off => _Off(
        onTurnOn: () {
          player.beatSenseEnabled = true;
        },
      ),
      BeatSenseState.unavailable => const _Note(
        icon: LucideIcons.circleAlert300,
        text:
            'Beat Sense can\'t read this song\'s beat, so songs will '
            'play one after another.',
      ),
      BeatSenseState.analysing => _Note(
        icon: LucideIcons.audioWaveform300,
        text:
            'Listening to "${current?.title ?? ''}": finding its beats, '
            'bars and key…',
        busy: true,
      ),
      BeatSenseState.ready || BeatSenseState.mixing => _Plan(
        current: current,
        next: status.next,
        from: player.analysis,
        to: player.nextAnalysis,
        plan: status.plan,
        mixing: status.state == BeatSenseState.mixing,
        why: status.why,
      ),
    };
  }
}

class _Off extends StatelessWidget {
  const _Off({required this.onTurnOn});

  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: _Note(
            icon: LucideIcons.audioWaveform300,
            text:
                'Beat Sense is off. Turn it on to hear songs mix into each '
                'other.',
          ),
        ),
        const SizedBox(width: 10),
        Pressable(
          onTap: onTurnOn,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: MsColors.accent,
              borderRadius: BorderRadius.circular(MsSizes.tileRadius),
            ),
            child: Text(
              'Turn on',
              style: MsText.tileLabel.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.busy = false});

  final IconData icon;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        busy
            ? const PlayingBars(size: 16)
            : Icon(icon, size: 18, color: MsColors.accentSoft),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: MsText.rowSubtitle.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _Plan extends StatelessWidget {
  const _Plan({
    required this.current,
    required this.next,
    required this.from,
    required this.to,
    required this.plan,
    required this.mixing,
    this.why,
  });

  final Track? current;
  final Track? next;
  final TrackAnalysis? from;
  final TrackAnalysis? to;
  final TransitionPlan? plan;
  final bool mixing;

  /// The DJ's reasoning, in DJ mode.
  final String? why;

  @override
  Widget build(BuildContext context) {
    final plan = this.plan;
    final white = Colors.white;
    final dim = white.withValues(alpha: 0.6);

    if (next == null) {
      return _Note(
        icon: LucideIcons.audioWaveform300,
        text: from == null
            ? 'Beat Sense will mix the next song in.'
            : 'This song: ${from!.bpm.round()} BPM in ${from!.key}. Beat '
                  'Sense is picking a song that mixes well after it.',
      );
    }

    final change = plan == null ? 0.0 : (plan.incomingRate - 1) * 100;
    final keyStep = from == null || to == null
        ? null
        : from!.key.camelotDistance(to!.key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const PlayingBars(size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mixing ? 'BEAT SENSE · MIXING' : 'BEAT SENSE · NEXT MIX',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MsText.overline.copyWith(color: MsColors.accentSoft),
              ),
            ),
            const SizedBox(width: 8),
            if (plan != null)
              PositionBuilder(
                builder: (context, p) {
                  final at = p.position.inMilliseconds / 1000;
                  final left = (plan.exitAt - at).clamp(0, 36000);
                  return Text(
                    mixing
                        ? '${(((at - plan.exitAt) / plan.length).clamp(0.0, 1.0) * 100).round()}%'
                        : 'in ${formatTime(Duration(milliseconds: (left * 1000).round()))}',
                    style: MsText.time.copyWith(color: white, fontSize: 12),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        _Song(track: current, analysis: from, label: 'NOW'),
        const SizedBox(height: 8),
        _Song(track: next, analysis: to, label: 'NEXT'),
        if (plan != null) ...[
          const SizedBox(height: 12),
          // The blend: outgoing fades as incoming rises, filled as it plays.
          PositionBuilder(
            builder: (context, p) {
              final at = p.position.inMilliseconds / 1000;
              final t = mixing
                  ? ((at - plan.exitAt) / plan.length).clamp(0.0, 1.0)
                  : 0.0;
              return _BlendBar(progress: t, style: plan.style);
            },
          ),
          const SizedBox(height: 10),
          Text(
            [
              MixCard.styleName(plan.style),
              if (plan.beatMatched && change.abs() >= 0.1)
                '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}% speed to match',
              if (plan.beatMatched && change.abs() < 0.1) 'same tempo',
              if (keyStep != null)
                keyStep == 0
                    ? 'same key'
                    : keyStep == 1
                    ? 'neighbouring keys'
                    : 'keys $keyStep steps apart',
              '${plan.length.round()} s blend',
            ].join(' · '),
            style: MsText.tileLabel.copyWith(color: white, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            why ?? MixCard.styleHow(plan.style),
            style: MsText.rowSubtitle.copyWith(
              color: dim,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
          if (!mixing) ...[const SizedBox(height: 12), _MixNow()],
        ],
      ],
    );
  }
}

class _Song extends StatelessWidget {
  const _Song({
    required this.track,
    required this.analysis,
    required this.label,
  });

  final Track? track;
  final TrackAnalysis? analysis;
  final String label;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final metric = MsText.time.copyWith(
      color: MsColors.accentSoft,
      fontSize: 11.5,
    );
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: MsText.overline.copyWith(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
            ),
          ),
        ),
        SizedBox.square(
          dimension: 36,
          child: track == null
              ? const SizedBox()
              : Artwork(art: track!.artwork, radius: 7),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            track?.title ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MsText.tileLabel.copyWith(
              color: Colors.white,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (a == null)
          Text('analysing…', style: metric)
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${a.bpm.round()} BPM', style: metric),
              Text(
                a.key.camelot,
                style: metric.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Two crossing level curves (out falls, in rises) with the played part
/// filled, so you can see where in the blend the music is.
class _BlendBar extends StatelessWidget {
  const _BlendBar({required this.progress, required this.style});

  final double progress;
  final TransitionStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: double.infinity,
      child: CustomPaint(
        painter: _BlendPainter(progress, style, Accent.of(context)),
      ),
    );
  }
}

class _BlendPainter extends CustomPainter {
  _BlendPainter(this.progress, this.style, this.accent);

  final double progress;
  final TransitionStyle style;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Bass swap and cut hand over sharply in the middle; blends are smooth.
    double incoming(double x) => switch (style) {
      TransitionStyle.cutOnBeat || TransitionStyle.dropCut => x < 0.9 ? 0 : 1,
      TransitionStyle.bassSwap => x < 0.5 ? x * 1.2 : 0.6 + (x - 0.5) * 0.8,
      _ => x,
    };
    Path curve(double Function(double) level) {
      final p = Path();
      for (var i = 0; i <= 40; i++) {
        final x = i / 40;
        final y = h - level(x) * (h - 2) - 1;
        i == 0 ? p.moveTo(x * w, y) : p.lineTo(x * w, y);
      }
      return p;
    }

    final played = Rect.fromLTWH(0, 0, w * progress, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    if (progress > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(played, const Radius.circular(4)),
        Paint()..color = accent.withValues(alpha: 0.22),
      );
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(
      curve((x) => 1 - incoming(x)),
      stroke..color = Colors.white.withValues(alpha: 0.55),
    );
    canvas.drawPath(curve(incoming), stroke..color = MsColors.accentSoft);
    if (progress > 0) {
      canvas.drawLine(
        Offset(w * progress, 0),
        Offset(w * progress, h),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_BlendPainter old) =>
      old.progress != progress || old.style != style || old.accent != accent;
}

/// Starts the blend at the next bar, so you can hear it now.
class _MixNow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final ready = player.canMixNow;
    return Row(
      children: [
        Semantics(
          button: true,
          enabled: ready,
          label: 'Mix now',
          child: Pressable(
            onTap: ready ? player.mixNow : null,
            child: AnimatedOpacity(
              duration: MsMotion.fast,
              opacity: ready ? 1 : 0.4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MsColors.accent,
                  borderRadius: BorderRadius.circular(MsSizes.tileRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.audioWaveform300,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mix now',
                      style: MsText.tileLabel.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ready
                ? 'or press Next for a quick mix'
                : 'Lining up the next song…',
            maxLines: 2,
            style: MsText.rowSubtitle.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

/// Beat Sense DJ on/off: plays the best part of each song and picks the next one
/// itself, blending into drops or cutting on the beat.
class _DjSwitch extends StatelessWidget {
  const _DjSwitch();

  @override
  Widget build(BuildContext context) {
    final player = PlayerScope.of(context);
    final on = player.djMode;
    return Semantics(
      button: true,
      toggled: on,
      label: 'Beat Sense DJ',
      child: Pressable(
        tilt: 0.04,
        onTap: () {
          player.djMode = !on;
          player.message.value = on
              ? 'Beat Sense DJ off · whole songs, mixed at the end'
              : 'Beat Sense DJ on · best parts, blended on the beat';
        },
        child: Row(
          children: [
            Icon(
              LucideIcons.disc3300,
              size: 18,
              color: on
                  ? MsColors.accentSoft
                  : Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Beat Sense DJ',
                    style: MsText.tileLabel.copyWith(color: Colors.white),
                  ),
                  Text(
                    on
                        ? 'Picks songs, cuts and blends on the beat'
                        : 'Off: whole songs, mixed at the end',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MsText.rowSubtitle.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // A small switch in the card's own style.
            AnimatedContainer(
              duration: MsMotion.fast,
              curve: MsMotion.curve,
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(3),
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: on
                    ? MsColors.accent
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
