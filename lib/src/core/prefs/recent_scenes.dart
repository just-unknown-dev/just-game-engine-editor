import 'package:flutter/foundation.dart';

import 'package:just_editor_core/host.dart';

/// The scenes opened lately, newest first: the Scenes list's Recent group,
/// its "recently opened" sort, and the start card's Reopen.
///
/// Kept with the session — where the last one left off — not with the
/// settings, so it is never exported. It follows a scene renamed or deleted
/// from the Scenes list; one removed any other way is dropped when read.
abstract final class RecentScenes {
  /// How many are remembered.
  static const int keep = 8;

  /// Newline-separated: a scene name never holds one.
  static final SettingPref<String> pref = SettingPref.text(
    OverlaySettingsPrefKeys.sessionRecentScenes,
    '',
  );

  /// The scene open when the editor was last closed: the plugin writes it.
  static final SettingPref<String> lastScene = SettingPref.text(
    OverlaySettingsPrefKeys.sessionLastScene,
    '',
  );

  static List<String> _decode(String raw) =>
      raw.split('\n').where((n) => n.isNotEmpty).toList();

  /// Newest first; only names in [existing], when it is given.
  static List<String> of(EditorPrefs prefs, {Iterable<String>? existing}) {
    final names = _decode(prefs.get(pref));
    if (existing == null) return names;
    final there = existing.toSet();
    return names.where(there.contains).toList();
  }

  /// A view of [of] that tells when it changes.
  static ValueListenable<String> watch(EditorPrefs prefs) => prefs.watch(pref);

  /// [name] was opened: it goes to the front.
  static Future<void> touch(EditorPrefs prefs, String name) {
    if (name.isEmpty) return Future.value();
    final names = of(prefs)
      ..remove(name)
      ..insert(0, name);
    return prefs.set(pref, names.take(keep).join('\n'));
  }

  /// [from] is now called [to], in the list and as the last scene.
  static Future<void> rename(EditorPrefs prefs, String from, String to) async {
    final names = [for (final n in of(prefs)) n == from ? to : n];
    await prefs.set(pref, names.join('\n'));
    if (prefs.get(lastScene) == from) await prefs.set(lastScene, to);
  }

  /// [name] is gone.
  static Future<void> forget(EditorPrefs prefs, String name) async {
    final names = of(prefs)..remove(name);
    await prefs.set(pref, names.join('\n'));
    if (prefs.get(lastScene) == name) await prefs.set(lastScene, '');
  }
}
