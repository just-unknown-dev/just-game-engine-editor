import 'package:flutter/widgets.dart';
import 'package:just_signals/just_signals.dart';

import '../../ui/overlay/settings/overlay_ui_settings.dart';
import 'editor_theme_data.dart';

/// The editor's current palette and the presets it can switch between.
///
/// A scope service. The built-in presets are the five accents the settings
/// dialog has always offered, over the classic palette; a module registers
/// its own. Widgets read the palette with `EditorTheme.of(context)` under an
/// [EditorThemeScope], which the overlay root provides.
class ThemeController {
  ThemeController({EditorThemeData initial = EditorThemeData.classic})
    : current = Signal(initial, debugLabel: 'theme');

  /// The five built-in accents, in the order they were once saved by index:
  /// id, label, colour.
  static const List<(String, String, Color)> builtIn = [
    ('sunrise', 'Sunrise', Color(0xFFF5746F)),
    ('mint', 'Mint', Color(0xFF5FD7A3)),
    ('cobalt', 'Cobalt', Color(0xFF5A8DFF)),
    ('amber', 'Amber', Color(0xFFFFC86B)),
    ('mono', 'Mono', Color(0xFFB7BDC8)),
  ];

  final Map<String, ThemePreset> _presets = {
    for (final (id, label, accent) in builtIn)
      id: ThemePreset(
        id: id,
        label: label,
        // Sunrise is the classic palette itself, not a copy near it.
        data: id == OverlayUiSettings.defaultThemeId
            ? EditorThemeData.classic
            : EditorThemeData.classic.withAccent(accent),
      ),
  };

  /// The theme in use.
  final Signal<EditorThemeData> current;

  /// The selected preset's id, or null after [set].
  final Signal<String?> currentId = Signal(null, debugLabel: 'themePreset');

  List<ThemePreset> get presets => List.unmodifiable(_presets.values);

  ThemePreset? preset(String id) => _presets[id];

  /// Adds or replaces a preset.
  void register(ThemePreset preset) => _presets[preset.id] = preset;

  /// Switches to the preset with [id]; unknown ids are ignored.
  void select(String id) {
    final preset = _presets[id];
    if (preset == null || currentId.value == id) return;
    current.value = preset.data;
    currentId.value = id;
  }

  /// Switches to a palette that is not a preset.
  void set(EditorThemeData data) {
    current.value = data;
    currentId.value = null;
  }

  void dispose() {
    current.dispose();
    currentId.dispose();
  }
}

/// Provides the current [EditorThemeData] to a subtree; rebuilds dependents
/// when the controller changes.
class EditorThemeScope extends InheritedNotifier<Signal<EditorThemeData>> {
  EditorThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller.current);

  /// The palette in force at [context], or the classic one outside any scope.
  static EditorThemeData of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<EditorThemeScope>()
          ?.notifier
          ?.value ??
      EditorThemeData.classic;
}
