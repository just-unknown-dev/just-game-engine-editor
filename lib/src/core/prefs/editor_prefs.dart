import 'package:flutter/foundation.dart';
import 'package:just_signals/just_signals.dart';

import '../../ui/overlay/settings/overlay_settings_store.dart';
import '../../ui/overlay/settings/overlay_ui_settings.dart';

/// A preference a module keeps in the editor's settings store, typed.
///
/// ```dart
/// static const showWaves = SettingPref.boolean('mygame.showWaves', true);
/// final on = scope.prefs.get(showWaves);
/// ```
class SettingPref<T> {
  const SettingPref(
    this.key, {
    required this.defaultValue,
    required this.encode,
    required this.decode,
  });

  static SettingPref<bool> boolean(String key, bool defaultValue) =>
      SettingPref(
        key,
        defaultValue: defaultValue,
        encode: (v) => v.toString(),
        decode: (raw) => raw == 'true',
      );

  static SettingPref<int> integer(String key, int defaultValue) => SettingPref(
    key,
    defaultValue: defaultValue,
    encode: (v) => v.toString(),
    decode: (raw) => int.tryParse(raw) ?? defaultValue,
  );

  static SettingPref<double> decimal(String key, double defaultValue) =>
      SettingPref(
        key,
        defaultValue: defaultValue,
        encode: (v) => v.toString(),
        decode: (raw) => double.tryParse(raw) ?? defaultValue,
      );

  static SettingPref<String> text(String key, String defaultValue) =>
      SettingPref(
        key,
        defaultValue: defaultValue,
        encode: (v) => v,
        decode: (raw) => raw,
      );

  /// Namespaced: `'mygame.showWaves'`.
  final String key;
  final T defaultValue;
  final String Function(T value) encode;
  final T Function(String raw) decode;
}

/// One editor's persisted preferences: the built-in overlay settings, typed,
/// and an open set of keys for whatever a module wants to remember.
///
/// Owned by the scope. Loads once, on first use, from the same store the
/// editor always wrote to, so nothing anyone saved before is lost.
class EditorPrefs {
  EditorPrefs({required this.store});

  final OverlaySettingsStore store;

  /// The built-in overlay settings. Watch it to rebuild on a change.
  final Signal<OverlayUiSettings> settings = Signal(
    const OverlayUiSettings.defaults(),
    debugLabel: 'overlaySettings',
  );

  bool _loaded = false;
  Future<void>? _loading;
  final Map<String, String> _raw = {};
  final Map<String, Signal<Object?>> _watched = {};

  /// Whether [load] has completed (successfully or not).
  bool get loaded => _loaded;

  /// Reads everything from the store, once; later calls await the first.
  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      settings.value = await store.loadSettings();
      _raw.addAll(await store.readAll());
      for (final entry in _watched.entries) {
        if (_raw.containsKey(entry.key)) {
          entry.value.value = _raw[entry.key];
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to load editor preferences: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _loaded = true;
    }
  }

  /// Applies and persists [next].
  Future<void> update(OverlayUiSettings next) async {
    settings.value = next;
    try {
      await store.saveSettings(next);
    } catch (error, stackTrace) {
      debugPrint('Failed to save overlay settings: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// The stored value of [pref], or its default.
  T get<T>(SettingPref<T> pref) {
    final raw = _raw[pref.key];
    return raw == null ? pref.defaultValue : pref.decode(raw);
  }

  /// Stores [value] for [pref] and tells anyone watching.
  Future<void> set<T>(SettingPref<T> pref, T value) async {
    final raw = pref.encode(value);
    _raw[pref.key] = raw;
    _watched[pref.key]?.value = raw;
    await store.writeRaw(pref.key, raw);
  }

  /// A listenable view of [pref]'s decoded value.
  ValueListenable<T> watch<T>(SettingPref<T> pref) {
    final raw = _watched.putIfAbsent(
      pref.key,
      () => Signal<Object?>(_raw[pref.key]),
    );
    return _DecodedListenable(raw, pref);
  }

  /// Raw access, for chrome that stored plain keys before prefs existed.
  Future<bool> readBool(String key, {required bool fallback}) =>
      store.readBoolByKey(key, fallback: fallback);
  Future<void> writeBool(String key, bool value) =>
      store.writeBoolByKey(key, value);
  Future<int> readInt(String key, {required int fallback}) =>
      store.readIntByKey(key, fallback: fallback);
  Future<void> writeInt(String key, int value) =>
      store.writeIntByKey(key, value);

  void dispose() {
    settings.dispose();
    for (final n in _watched.values) {
      n.dispose();
    }
  }
}

class _DecodedListenable<T> extends ValueListenable<T> {
  const _DecodedListenable(this._raw, this._pref);
  final Signal<Object?> _raw;
  final SettingPref<T> _pref;

  @override
  T get value {
    final raw = _raw.value;
    return raw is String ? _pref.decode(raw) : _pref.defaultValue;
  }

  @override
  void addListener(VoidCallback listener) => _raw.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _raw.removeListener(listener);
}
