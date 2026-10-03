/// Tidies the names files on a phone come with, so lists read like a music
/// library rather than a file manager.
library;

const unknownArtist = 'Unknown artist';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _date(String yyyymmdd) {
  final y = int.tryParse(yyyymmdd.substring(0, 4));
  final m = int.tryParse(yyyymmdd.substring(4, 6));
  final d = int.tryParse(yyyymmdd.substring(6, 8));
  if (y == null || m == null || d == null || m < 1 || m > 12) return yyyymmdd;
  return '${_months[m - 1]} $d, $y';
}

final _whatsApp = RegExp(r'^(?:AUD|PTT)-(\d{8})-WA(\d{4})$');
final _recording = RegExp(
  r'^(?:rec|record|recording|voice)[\s_-]*0*(\d+)$',
  caseSensitive: false,
);
final _stamp = RegExp(r'^(?:[A-Za-z]+[_-])?(\d{8})[_-]\d{6}$');
final _extension = RegExp(
  r'\.(mp3|m4a|aac|flac|wav|ogg|opus|wma)$',
  caseSensitive: false,
);
final _noise = RegExp(
  r'\s*[\(\[](?:official\s*)?(?:music\s*)?(?:video|audio|lyrics?|lyric video|visuali[sz]er|hd|hq|4k)[\)\]]',
  caseSensitive: false,
);

/// A readable title for a song whose tag may just be its file name.
String tidyTitle(String raw) {
  var t = raw.trim().replaceAll(_extension, '');
  final wa = _whatsApp.firstMatch(t);
  if (wa != null) {
    final n = int.parse(wa.group(2)!);
    return 'Audio · ${_date(wa.group(1)!)}${n > 0 ? ' (${n + 1})' : ''}';
  }
  final rec = _recording.firstMatch(t);
  if (rec != null) return 'Recording ${int.parse(rec.group(1)!)}';
  final stamp = _stamp.firstMatch(t);
  if (stamp != null) return 'Recording · ${_date(stamp.group(1)!)}';
  t = t.replaceAll(_noise, '');
  if (!t.contains(' ')) t = t.replaceAll('_', ' ');
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return t.isEmpty ? raw : t;
}

/// "Artist - Title" in the title with no artist tag: split it.
(String title, String? artist) splitArtist(String title, String? artist) {
  if (artist != null) return (title, artist);
  final i = title.indexOf(' - ');
  if (i <= 0 || i >= title.length - 3) return (title, null);
  return (title.substring(i + 3).trim(), title.substring(0, i).trim());
}
