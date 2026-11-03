import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/beat_sense/analysis/track_analysis.dart';
import 'package:music_sense/beat_sense/mix_script.dart';
import 'package:music_sense/beat_sense/transition.dart';

import 'dj_test.dart' show song;

/// The value of a flattened lane at time [t] (straight lines between).
double at(List<double> lane, double t) {
  if (t <= lane[0]) return lane[1];
  for (var i = 2; i < lane.length; i += 2) {
    if (t < lane[i]) {
      final f = (t - lane[i - 2]) / (lane[i] - lane[i - 2]);
      return lane[i - 1] + (lane[i + 1] - lane[i - 1]) * f;
    }
  }
  return lane.last;
}

void main() {
  group('key matching', () {
    test('a semitone shift that lands on a neighbour key', () {
      const aMinor = MusicalKey(9, minor: true); // 8A
      const bFlatMinor = MusicalKey(10, minor: true); // 3A: far away
      final s = TransitionPlanner.keyMatch(aMinor, bFlatMinor);
      expect(s, -1); // down to A minor itself
      expect(
        aMinor.camelotDistance(bFlatMinor.transpose(s)),
        lessThanOrEqualTo(1),
      );
    });

    test('keys that already mix are left alone', () {
      const aMinor = MusicalKey(9, minor: true); // 8A
      const eMinor = MusicalKey(4, minor: true); // 9A
      expect(TransitionPlanner.keyMatch(aMinor, eMinor), 0);
    });

    test('the planner shifts only when it may and it helps', () {
      final a = song(key: const MusicalKey(9, minor: true));
      final b = song(bpm: 123, key: const MusicalKey(10, minor: true));
      expect(const TransitionPlanner().plan(a, b).incomingSemitones, 0);
      final shifted = const TransitionPlanner(keyShift: true).plan(a, b);
      expect(shifted.incomingSemitones, -1);
      expect(shifted.style, TransitionStyle.blend); // now in key: a blend
    });

    test('the outgoing song\'s own shift is taken into account', () {
      final a = song(key: const MusicalKey(9, minor: true));
      final b = song(bpm: 123, key: const MusicalKey(10, minor: true));
      // A already plays a semitone up (B flat minor): B matches as is.
      final p = const TransitionPlanner(keyShift: true)
          .plan(a, b, fromSemitones: 1);
      expect(p.incomingSemitones, 0);
    });
  });

  group('DJ scripts', () {
    TransitionPlan plan(TransitionStyle style) => TransitionPlan(
      style: style,
      exitAt: 100,
      entryAt: 10,
      length: 16,
      incomingRate: 0.97,
      rampBack: 8,
      incomingGainDb: 0,
      outgoingGainDb: 0,
    );

    for (final style in [TransitionStyle.blend, TransitionStyle.bassSwap]) {
      test('${style.name}: the bass changes hands on the middle downbeat', () {
        final l = MixScript.lanes(plan(style));
        // Before the swap only the old song has bass; after, only the new.
        expect(at(l['inLow']!, 105), MixScript.kill);
        expect(at(l['outLow']!, 105), 0);
        expect(at(l['inLow']!, 108.1), 0);
        expect(at(l['outLow']!, 108.1), MixScript.kill);
        // Never two full basslines at once.
        for (var t = 100.0; t <= 116; t += 0.05) {
          final both = at(l['inLow']!, t) > -6 && at(l['outLow']!, t) > -6;
          expect(both, isFalse, reason: 'both basslines at $t');
        }
        // The new song arrives, the old one leaves.
        expect(at(l['inGain']!, 100), 0);
        expect(at(l['inGain']!, 116), 1);
        expect(at(l['outGain']!, 100), 1);
        expect(at(l['outGain']!, 116), 0);
        expect(at(l['outFilter']!, 116), greaterThan(0.3));
      });
    }

    test('a drop cut stays silent until the downbeat, then swaps', () {
      final l = MixScript.lanes(plan(TransitionStyle.dropCut));
      expect(at(l['inGain']!, 110), 0);
      expect(at(l['outGain']!, 110), 1);
      expect(at(l['inGain']!, 116), 1);
      expect(at(l['outGain']!, 116), 0);
    });

    test('a crossfade keeps the power level', () {
      final l = MixScript.lanes(plan(TransitionStyle.crossfade));
      for (var t = 100.0; t <= 116; t += 2) {
        final a = at(l['outGain']!, t), b = at(l['inGain']!, t);
        expect(a * a + b * b, closeTo(1, 0.03));
      }
    });

    test('the engine gets the plan\'s timing, tempo and key', () {
      final p = plan(TransitionStyle.blend).copyWith(incomingSemitones: 1);
      final m = MixScript.toEngine(p);
      expect(m['exit'], 100);
      expect(m['entry'], 10);
      expect(m['rate'], 0.97);
      expect(m['semitones'], 1.0);
      expect((m['lanes'] as Map).keys, contains('inLow'));
    });
  });
}
