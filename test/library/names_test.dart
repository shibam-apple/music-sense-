import 'package:flutter_test/flutter_test.dart';
import 'package:music_sense/library/names.dart';

void main() {
  test('WhatsApp audio and recordings get readable names', () {
    expect(tidyTitle('AUD-20251210-WA0000'), 'Audio · Dec 10, 2025');
    expect(tidyTitle('AUD-20241221-WA0001'), 'Audio · Dec 21, 2024 (2)');
    expect(tidyTitle('Record-024'), 'Recording 24');
    expect(tidyTitle('Recording_20230105_141233'), 'Recording · Jan 5, 2023');
  });

  test('file name noise is removed, real titles kept', () {
    expect(tidyTitle('Blinding_Lights.mp3'), 'Blinding Lights');
    expect(tidyTitle('Levitating (Official Video)'), 'Levitating');
    expect(tidyTitle('Bagam Bagaan - Bengali'), 'Bagam Bagaan - Bengali');
  });

  test('"Artist - Title" splits only without an artist tag', () {
    expect(splitArtist('Knox - Sneakers', null), ('Sneakers', 'Knox'));
    expect(
      splitArtist('Knox - Sneakers', 'BangersOnly'),
      ('Knox - Sneakers', 'BangersOnly'),
    );
  });
}
