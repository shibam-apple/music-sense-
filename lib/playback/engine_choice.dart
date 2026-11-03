import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Which playback engine Beat Sense uses, kept on the phone.
///
/// - [studio]: the native engine (sample-exact beat lock, DJ EQ, filters,
///   key matching).
/// - [classic]: the earlier engine on the standard players, kept as a
///   fallback.
enum EngineChoice {
  studio,
  classic;

  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/engine.txt');

  static Future<EngineChoice> load() async {
    try {
      final f = await _file();
      if (await f.exists() && (await f.readAsString()).trim() == 'classic') {
        return classic;
      }
    } catch (_) {}
    return studio;
  }

  static Future<void> save(EngineChoice choice) async {
    try {
      await (await _file()).writeAsString(choice.name);
    } catch (_) {}
  }
}

/// Makes the running engine known to the pages (the Account page shows it).
class EngineScope extends InheritedWidget {
  const EngineScope({super.key, required this.engine, required super.child});

  final EngineChoice engine;

  static EngineChoice of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EngineScope>()?.engine ??
      EngineChoice.classic;

  @override
  bool updateShouldNotify(EngineScope old) => old.engine != engine;
}
