import 'dart:math' as math;
import 'dart:typed_data';

/// Real-input FFT of a fixed power-of-two size, with a Hann window.
///
/// Reuses its buffers, so one instance should not be shared across
/// isolates or used re-entrantly.
class Fft {
  Fft(this.size)
    : assert(size > 0 && (size & (size - 1)) == 0, 'size must be 2^n'),
      _re = Float64List(size),
      _im = Float64List(size),
      _window = Float64List(size),
      _cos = Float64List(size ~/ 2),
      _sin = Float64List(size ~/ 2),
      _reversed = Int32List(size) {
    for (var i = 0; i < size; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / size);
    }
    for (var i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / size);
      _sin[i] = -math.sin(2 * math.pi * i / size);
    }
    final bits = size.bitLength - 1;
    for (var i = 0; i < size; i++) {
      var r = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) r |= 1 << (bits - 1 - b);
      }
      _reversed[i] = r;
    }
  }

  final int size;
  final Float64List _re, _im, _window, _cos, _sin;
  final Int32List _reversed;

  int get bins => size ~/ 2 + 1;

  /// Writes the magnitude spectrum of `samples[start, start + size)` into
  /// [out] (length [bins]). Samples past the end of the input read as zero.
  void magnitudes(Float32List samples, int start, Float64List out) {
    for (var i = 0; i < size; i++) {
      final j = start + i;
      final s = j < samples.length ? samples[j] : 0.0;
      final k = _reversed[i];
      _re[k] = s * _window[i];
      _im[k] = 0;
    }
    for (var half = 1; half < size; half <<= 1) {
      final step = size ~/ (half * 2);
      for (var i = 0; i < size; i += half * 2) {
        for (var j = 0; j < half; j++) {
          final wr = _cos[j * step], wi = _sin[j * step];
          final a = i + j, b = a + half;
          final tr = _re[b] * wr - _im[b] * wi;
          final ti = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - tr;
          _im[b] = _im[a] - ti;
          _re[a] += tr;
          _im[a] += ti;
        }
      }
    }
    for (var i = 0; i < bins; i++) {
      out[i] = math.sqrt(_re[i] * _re[i] + _im[i] * _im[i]);
    }
  }
}
