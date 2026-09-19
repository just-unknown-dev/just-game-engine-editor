import 'package:flutter/widgets.dart';
import 'package:just_signals/just_signals.dart';

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

  static const List<(String, String, Color)> _builtIn = [
    ('sunrise', 'Sunrise', Color(0xFFFF6F61)),
    ('mint', 'Mint', Color(0xFF5FD7A3)),
    ('cobalt', 'Cobalt', Color(0xFF5A8DFF)),
    ('amber', 'Amber', Color(0xFFFFC86B)),
    ('mono', 'Mono', Color(0xFFB7BDC8)),
  ];

  final Map<String, ThemePreset> _presets = {
    for (final (id, label, accent) in _builtIn)
      id: ThemePreset(
        id: id,
        label: label,
        data: EditorThemeData.classic.withAccent(accent),
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
