import 'dart:convert';

import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/just_editor_core.dart';

/// The Asset Store's settings, kept per user on this machine.
abstract final class StoreSettings {
  /// Whether the official catalog is read.
  static final SettingPref<bool> official = SettingPref.boolean(
    'editor.store.official',
    true,
  );

  /// Other catalogs: a JSON list of `{url, name, enabled}`.
  static final SettingPref<String> customSources = SettingPref.text(
    'editor.store.sources',
    '',
  );

  /// Whether the store lists experimental items.
  static final SettingPref<bool> showExperimental = SettingPref.boolean(
    'editor.store.experimental',
    false,
  );

  /// The Flutter SDK folder; empty to use the project's.
  static final SettingPref<String> sdkPath = SettingPref.text(
    'editor.store.sdk',
    '',
  );

  /// The catalogs to read, official first.
  static List<SourceConfig> sources(EditorPrefs prefs) => [
    if (prefs.get(official)) SourceConfig.official,
    ...custom(prefs),
  ];

  /// The catalogs the user added.
  static List<SourceConfig> custom(EditorPrefs prefs) {
    final text = prefs.get(customSources);
    if (text.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(text);
      if (list is! List) return const [];
      return [
        for (final s in list)
          if (s is Map) SourceConfig.fromJson(JsonFields(s)),
      ];
    } on Object {
      return const [];
    }
  }

  /// Saves the catalogs the user added.
  static Future<void> setCustom(EditorPrefs prefs, List<SourceConfig> list) =>
      prefs.set(customSources, jsonEncode([for (final s in list) s.toJson()]));
}
