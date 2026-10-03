import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';
import 'track_analysis.dart';

/// Analyses decoded mono audio for Beat Sense.
///
/// Pipeline: short-time spectrum → onset strength (spectral flux) → tempo
/// by autocorrelation → beat grid by dynamic programming → bars from the
/// kick-drum band → phrases from energy changes → key from chroma.
/// Pure Dart, so it runs in an isolate on any platform.
class BeatSenseAnalyzer {
  BeatSenseAnalyzer({this.fftSize = 1024, this.hop = 256});

  final int fftSize;
  final int hop;

  static const minBpm = 70.0;
  static const maxBpm = 190.0;

  TrackAnalysis analyze(Float32List samples, int sampleRate) {
    final fps = sampleRate / hop;
    final duration = samples.length / sampleRate;
    final f = _frames(samples, sampleRate);

    final onset = _normalise(_localContrast(f.flux, (fps * 0.4).round()));
    final kick = _normalise(_localContrast(f.lowFlux, (fps * 0.4).round()));

    final tempo = _tempo(_smooth(onset), fps);
    final beatFrames =
        _onTheBeat(_trackBeats(onset, tempo.period), kick, tempo.period);
    final beats = [for (final b in beatFrames) _frameTime(b)];
    final bpm = _refineBpm(beats, 60 * fps / tempo.period);

    final downbeatPhase = _barPhase(beatFrames, kick, f.rms);
    final downbeats = [
      for (var i = downbeatPhase; i < beats.length; i += 4) beats[i],
    ];
    final barEnergy = _barEnergy(downbeats, f.rms, fps, duration);
    final phrases = _phrases(downbeats, barEnergy);

    final keyResult = _key(f.chroma);
    final loudness = _loudness(f.rms);
    final introOutro = _introOutro(downbeats, barEnergy, duration);

    final onsetDensity =
        onset.where((v) => v > 0.3).length / math.max(1, onset.length);
    final level = ((loudness + 40) / 34).clamp(0.0, 1.0);
    final energy = (0.65 * level + 0.35 * (onsetDensity * 4).clamp(0.0, 1.0))
        .clamp(0.0, 1.0);

    return TrackAnalysis(
      duration: duration,
      bpm: bpm,
      beatConfidence: tempo.confidence,
      beats: beats,
      downbeats: downbeats,
      phrases: phrases,
      key: keyResult.key,
      keyConfidence: keyResult.confidence,
      loudnessDb: loudness,
      energy: energy,
      barEnergy: barEnergy,
      introEnd: introOutro.$1,
      outroStart: introOutro.$2,
    );
  }

  /// Time of the onset that peaks in frame [i], in seconds: the frame
  /// centre plus one hop, the measured delay of a windowed spectral-flux
  /// peak behind the attack.
  double _frameTime(int i) => (i * hop + fftSize / 2 + hop) / _sampleRate;
  late int _sampleRate;

  _Frames _frames(Float32List samples, int sampleRate) {
    _sampleRate = sampleRate;
    final fft = Fft(fftSize);
    final bins = fft.bins;
    final count = math.max(1, (samples.length - fftSize) ~/ hop + 1);
    final binHz = sampleRate / fftSize;

    // Map each bin between 100 Hz and 5 kHz to its pitch class.
    final pitchClass = Int8List(bins)..fillRange(0, bins, -1);
    for (var b = 1; b < bins; b++) {
      final hz = b * binHz;
      if (hz < 100 || hz > 5000) continue;
      final midi = 69 + 12 * math.log(hz / 440) / math.ln2;
      pitchClass[b] = midi.round() % 12;
    }

    // 24 log-spaced bands from 30 Hz up; each counts equally toward the
    // onset strength, so a noisy hi-hat doesn't outweigh a kick drum.
    const bandCount = 24;
    final nyquist = sampleRate / 2;
    final band = Int8List(bins)..fillRange(0, bins, -1);
    for (var b = 1; b < bins; b++) {
      final hz = b * binHz;
      if (hz < 30) continue;
      final i = (math.log(hz / 30) / math.log(nyquist / 30) * bandCount)
          .floor()
          .clamp(0, bandCount - 1);
      band[b] = i;
    }
    final lowBands = (math.log(150 / 30) / math.log(nyquist / 30) * bandCount)
        .ceil();

    final flux = Float64List(count);
    final lowFlux = Float64List(count);
    final rms = Float64List(count);
    final chroma = Float64List(12);
    final mag = Float64List(bins);
    final bandNow = Float64List(bandCount), bandPrev = Float64List(bandCount);

    for (var i = 0; i < count; i++) {
      final start = i * hop;
      fft.magnitudes(samples, start, mag);

      var sum = 0.0;
      for (var j = 0; j < hop && start + j < samples.length; j++) {
        final s = samples[start + j];
        sum += s * s;
      }
      rms[i] = math.sqrt(sum / hop);

      bandNow.fillRange(0, bandCount, 0);
      for (var b = 1; b < bins; b++) {
        final k = band[b];
        if (k >= 0) bandNow[k] += mag[b];
        final pc = pitchClass[b];
        if (pc >= 0) chroma[pc] += mag[b];
      }
      var total = 0.0, low = 0.0;
      for (var k = 0; k < bandCount; k++) {
        final m = math.log(1 + 10 * bandNow[k]);
        final d = m - bandPrev[k];
        if (d > 0) {
          total += d;
          if (k < lowBands) low += d;
        }
        bandPrev[k] = m;
      }
      flux[i] = total;
      lowFlux[i] = low;
    }
    return _Frames(flux, lowFlux, rms, chroma);
  }

  /// Light smoothing so beat periods that fall between frames still
  /// correlate cleanly.
  Float64List _smooth(Float64List x) {
    const k = [0.1, 0.25, 0.3, 0.25, 0.1];
    final out = Float64List(x.length);
    for (var i = 0; i < x.length; i++) {
      var s = 0.0;
      for (var j = 0; j < k.length; j++) {
        final idx = i + j - 2;
        if (idx >= 0 && idx < x.length) s += k[j] * x[idx];
      }
      out[i] = s;
    }
    return out;
  }

  /// If the low-frequency hits (kick, snare body) sit between the tracked
  /// beats rather than on them, the tracker locked to the off-beat: shift
  /// the grid by half a beat.
  List<int> _onTheBeat(List<int> beats, Float64List kick, double period) {
    if (beats.length < 8) return beats;
    double around(int f) {
      var m = 0.0;
      for (var j = math.max(0, f - 2); j <= math.min(kick.length - 1, f + 2); j++) {
        m = math.max(m, kick[j]);
      }
      return m;
    }

    final half = (period / 2).round();
    var on = 0.0, off = 0.0;
    for (final b in beats) {
      on += around(b);
      off += around(b + half);
    }
    if (off <= on * 1.2) return beats;
    return [
      for (final b in beats)
        if (b + half < kick.length) b + half,
    ];
  }

  /// Subtracts a moving average and keeps the positive part, so steady
  /// sounds don't read as onsets.
  Float64List _localContrast(Float64List x, int radius) {
    final out = Float64List(x.length);
    final prefix = Float64List(x.length + 1);
    for (var i = 0; i < x.length; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }
    for (var i = 0; i < x.length; i++) {
      final lo = math.max(0, i - radius), hi = math.min(x.length, i + radius + 1);
      final mean = (prefix[hi] - prefix[lo]) / (hi - lo);
      out[i] = math.max(0, x[i] - mean);
    }
    return out;
  }

  Float64List _normalise(Float64List x) {
    var peak = 0.0;
    for (final v in x) {
      if (v > peak) peak = v;
    }
    if (peak == 0) return x;
    for (var i = 0; i < x.length; i++) {
      x[i] /= peak;
    }
    return x;
  }

  /// Picks the beat period (in frames) whose autocorrelation is strongest,
  /// weighted toward 120 BPM so half/double-tempo errors are less likely.
  ({double period, double confidence}) _tempo(Float64List onset, double fps) {
    final minLag = (60 * fps / maxBpm).floor();
    final maxLag = (60 * fps / minBpm).ceil();
    final n = onset.length;
    if (n < maxLag * 4) {
      return (period: 60 * fps / 120, confidence: 0);
    }

    double ac(int lag) {
      var s = 0.0;
      for (var i = lag; i < n; i++) {
        s += onset[i] * onset[i - lag];
      }
      return s / (n - lag);
    }

    final scores = <int, double>{};
    for (var lag = minLag; lag <= maxLag; lag++) {
      scores[lag] = ac(lag);
    }
    var zero = 0.0;
    for (final v in onset) {
      zero += v * v;
    }
    zero /= n;

    // Reward lags whose double also lines up (true beats repeat every bar).
    double weighted(int lag) {
      final bpm = 60 * fps / lag;
      final prior = math.exp(-0.5 * math.pow(math.log(bpm / 120) / math.ln2 / 0.9, 2));
      final twice = lag * 2 <= maxLag * 2 ? ac(lag * 2) : 0.0;
      return (scores[lag]! + 0.5 * twice) * prior;
    }

    var best = minLag;
    var bestScore = -1.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      final s = weighted(lag);
      if (s > bestScore) {
        bestScore = s;
        best = lag;
      }
    }

    // Parabolic interpolation around the peak for sub-frame precision.
    var period = best.toDouble();
    if (best > minLag && best < maxLag) {
      final a = weighted(best - 1), b = bestScore, c = weighted(best + 1);
      final denom = a - 2 * b + c;
      if (denom != 0) period += 0.5 * (a - c) / denom;
    }

    final confidence = zero == 0 ? 0.0 : (scores[best]! / zero).clamp(0.0, 1.0);
    return (period: period, confidence: confidence);
  }

  /// Ellis-style dynamic programming beat tracker: each beat should sit on
  /// a strong onset and about one period after the previous beat.
  List<int> _trackBeats(Float64List onset, double period) {
    final n = onset.length;
    const tightness = 120.0;
    final score = Float64List(n);
    final back = Int32List(n)..fillRange(0, n, -1);
    final lo = (period / 2).round(), hi = (period * 2).round();

    for (var t = 0; t < n; t++) {
      var best = 0.0;
      var from = -1;
      for (var d = lo; d <= hi; d++) {
        final p = t - d;
        if (p < 0) break;
        final penalty = math.log(d / period);
        final s = score[p] - tightness * penalty * penalty;
        if (from < 0 || s > best) {
          best = s;
          from = p;
        }
      }
      score[t] = onset[t] + (from >= 0 ? math.max(0, best) : 0);
      back[t] = from >= 0 && best > 0 ? from : -1;
    }

    // Start from the best-scoring frame in the last period.
    var end = n - 1;
    for (var t = math.max(0, n - period.ceil()); t < n; t++) {
      if (score[t] > score[end]) end = t;
    }
    final beats = <int>[];
    for (var t = end; t >= 0; t = back[t]) {
      beats.add(t);
      if (back[t] < 0) break;
    }
    // Drop beats before the music starts (silence scores ~0).
    final out = beats.reversed.toList();
    while (out.length > 1 && onset[out.first] < 0.02) {
      out.removeAt(0);
    }
    return out;
  }

  double _refineBpm(List<double> beats, double fallback) {
    if (beats.length < 8) return fallback;
    final gaps = [
      for (var i = 1; i < beats.length; i++) beats[i] - beats[i - 1],
    ]..sort();
    final median = gaps[gaps.length ~/ 2];
    // Least-squares slope over beats whose gap is near the median.
    final keep = <(int, double)>[];
    var index = 0;
    keep.add((0, beats.first));
    for (var i = 1; i < beats.length; i++) {
      final g = beats[i] - beats[i - 1];
      index += (g / median).round().clamp(1, 4);
      keep.add((index, beats[i]));
    }
    final n = keep.length;
    final mx = keep.fold(0.0, (s, e) => s + e.$1) / n;
    final my = keep.fold(0.0, (s, e) => s + e.$2) / n;
    var num = 0.0, den = 0.0;
    for (final (x, y) in keep) {
      num += (x - mx) * (y - my);
      den += (x - mx) * (x - mx);
    }
    if (den == 0) return fallback;
    final bpm = 60 / (num / den);
    return (bpm * 100).round() / 100;
  }

  /// Which of every four beats starts a bar: the one with the most kick
  /// drum and level, as most music lands its kick on beat one.
  int _barPhase(List<int> beats, Float64List kick, Float64List rms) {
    if (beats.length < 8) return 0;
    final strength = List<double>.filled(4, 0);
    final counts = List<int>.filled(4, 0);
    for (var i = 0; i < beats.length; i++) {
      final f = beats[i];
      var k = 0.0, r = 0.0;
      for (var j = math.max(0, f - 1); j <= math.min(kick.length - 1, f + 2); j++) {
        k = math.max(k, kick[j]);
        r = math.max(r, rms[j]);
      }
      strength[i % 4] += k + 0.5 * r;
      counts[i % 4]++;
    }
    var best = 0;
    for (var p = 1; p < 4; p++) {
      if (strength[p] / counts[p] > strength[best] / counts[best]) best = p;
    }
    return best;
  }

  List<double> _barEnergy(
      List<double> downbeats, Float64List rms, double fps, double duration) {
    if (downbeats.isEmpty) return const [];
    final values = <double>[];
    for (var i = 0; i < downbeats.length; i++) {
      final from = (downbeats[i] * fps).floor();
      final to = ((i + 1 < downbeats.length ? downbeats[i + 1] : duration) * fps)
          .floor()
          .clamp(from + 1, rms.length);
      var s = 0.0;
      for (var f = from; f < to && f < rms.length; f++) {
        s += rms[f] * rms[f];
      }
      values.add(math.sqrt(s / math.max(1, to - from)));
    }
    final peak = values.reduce(math.max);
    return [for (final v in values) peak == 0 ? 0 : v / peak];
  }

  /// Phrases are 8-bar blocks. Picks the bar offset where energy changes
  /// most often lines up with block edges.
  List<double> _phrases(List<double> downbeats, List<double> barEnergy) {
    if (downbeats.length < 16) {
      return [if (downbeats.isNotEmpty) downbeats.first];
    }
    double change(int bar) {
      if (bar < 2 || bar + 2 > barEnergy.length) return 0;
      final before = (barEnergy[bar - 2] + barEnergy[bar - 1]) / 2;
      final after = (barEnergy[bar] + barEnergy[bar + 1]) / 2;
      return (after - before).abs();
    }

    var bestOffset = 0;
    var bestScore = -1.0;
    for (var offset = 0; offset < 8; offset++) {
      var s = 0.0;
      for (var bar = offset; bar < downbeats.length; bar += 8) {
        s += change(bar);
      }
      // Slight preference for phrases that start at the first bar.
      if (offset == 0) s *= 1.05;
      if (s > bestScore) {
        bestScore = s;
        bestOffset = offset;
      }
    }
    return [
      for (var bar = bestOffset; bar < downbeats.length; bar += 8)
        downbeats[bar],
    ];
  }

  /// Krumhansl–Kessler key profiles correlated with the track's chroma.
  ({MusicalKey key, double confidence}) _key(Float64List chroma) {
    const major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
    const minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];

    double correlate(List<double> profile, int tonic) {
      var mx = 0.0, my = 0.0;
      for (var i = 0; i < 12; i++) {
        mx += chroma[i];
        my += profile[i];
      }
      mx /= 12;
      my /= 12;
      var num = 0.0, dx = 0.0, dy = 0.0;
      for (var i = 0; i < 12; i++) {
        final x = chroma[(i + tonic) % 12] - mx;
        final y = profile[i] - my;
        num += x * y;
        dx += x * x;
        dy += y * y;
      }
      return dx == 0 || dy == 0 ? 0 : num / math.sqrt(dx * dy);
    }

    final scores = <(MusicalKey, double)>[
      for (var t = 0; t < 12; t++) ...[
        (MusicalKey(t, minor: false), correlate(major, t)),
        (MusicalKey(t, minor: true), correlate(minor, t)),
      ],
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final confidence = (scores[0].$2 - scores[1].$2).clamp(0.0, 1.0) * 4;
    return (key: scores[0].$1, confidence: confidence.clamp(0.0, 1.0));
  }

  /// Mean power of the frames that aren't near-silent, in dBFS.
  double _loudness(Float64List rms) {
    double db(double power) => 10 * math.log(power) / math.ln10;
    final audible = [
      for (final r in rms)
        if (r > 1e-4) r * r,
    ];
    if (audible.isEmpty) return -90;
    final mean = audible.reduce((a, b) => a + b) / audible.length;
    // Second pass: drop frames 20 dB under the mean (gaps, fades).
    final gate = mean / 100;
    final loud = [
      for (final p in audible)
        if (p > gate) p,
    ];
    return db(loud.reduce((a, b) => a + b) / loud.length);
  }

  /// The intro ends at the first bar that reaches most of the track's
  /// typical level; the outro starts after the last such bar.
  (double, double) _introOutro(
      List<double> downbeats, List<double> barEnergy, double duration) {
    if (barEnergy.length < 4) return (0, duration);
    final sorted = [...barEnergy]..sort();
    final typical = sorted[(sorted.length * 0.6).floor()];
    final threshold = typical * 0.75;
    var first = 0;
    while (first < barEnergy.length - 1 && barEnergy[first] < threshold) {
      first++;
    }
    var last = barEnergy.length - 1;
    while (last > first && barEnergy[last] < threshold) {
      last--;
    }
    final outro = last + 1 < downbeats.length ? downbeats[last + 1] : duration;
    return (downbeats[first], outro);
  }
}

class _Frames {
  _Frames(this.flux, this.lowFlux, this.rms, this.chroma);

  final Float64List flux, lowFlux, rms, chroma;
}
