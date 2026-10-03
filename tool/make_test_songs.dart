// Writes WAV test songs with a known tempo, bars and key, for on-device
// Beat Sense tests. Usage: dart run tool/make_test_songs.dart <out dir>
import 'dart:io';
import 'dart:typed_data';

import '../test/beat_sense/synth.dart';

const sampleRate = 44100;

void main(List<String> args) {
  final out = Directory(args.isEmpty ? 'build/test_songs' : args.first)
    ..createSync(recursive: true);
  for (final (name, bpm, chords) in const [
    ('beat_test_120', 120.0, ['Am', 'F', 'C', 'G']),
    ('beat_test_124', 124.0, ['C', 'F', 'G', 'Am']),
  ]) {
    final pcm = drumLoop(
      bpm: bpm,
      seconds: 80,
      sampleRate: sampleRate,
      progression: chords,
      gain: 0.8,
    );
    File('${out.path}/$name.wav').writeAsBytesSync(_wav(pcm));
    stdout.writeln('wrote ${out.path}/$name.wav');
  }
}

Uint8List _wav(Float32List pcm) {
  final data = ByteData(44 + pcm.length * 2);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcm.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcm.length * 2, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    data.setInt16(44 + i * 2, (pcm[i] * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
