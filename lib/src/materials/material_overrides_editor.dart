import 'package:flutter/material.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// The inspector's editors for an entity's own material values —
/// `Material2D.overrides`, `ScreenMaterial.overrides`,
/// `MaterialOverrides3D.values` — in place of the editor's JSON one.
abstract final class MaterialOverrideEditors {
  /// By field type id, for the project in the working directory.
  static Map<String, FieldEditorBuilder> get all => forRoot(null);

  /// By field type id, for the project at [root] (the working directory
  /// when null).
  static Map<String, FieldEditorBuilder> forRoot(String? root) => {
    MaterialOverridesFieldType.material2D.id: (c) =>
        MaterialOverridesEditor(context: c, flat: true, root: root),
    MaterialOverridesFieldType.material3D.id: (c) =>
        MaterialOverridesEditor(context: c, flat: false, root: root),
  };
}

/// An entity's own values for its material: each with an editor of its
/// kind (a number, a colour, a pair) and a way to remove it, and a list
/// of the values it could have — those its material can change, 2-D
/// values for the effects its material has on — starting from the
/// material's own. A value being dragged or picked shows at once; letting
/// go is one undo step.
class MaterialOverridesEditor extends StatelessWidget {
  const MaterialOverridesEditor({
    super.key,
    required this.context,
    required this.flat,
    this.root,
  });

  /// The field being edited.
  final FieldEditorContext context;

  /// Whether the values are a 2-D material's (otherwise a 3-D one's).
  final bool flat;

  /// The project folder material paths are under; the working directory
  /// when null.
  final String? root;

  /// The values, by key.
  Map<String, Object> get values => {
    for (final MapEntry(:key, :value)
        in (context.value as Map? ?? const {}).entries)
      if (key is String && value != null) key: value as Object,
  };

  String get _root => (root ?? Directory.current.path).replaceAll(r'\', '/');

  // Each material file read, by its absolute path, with when it changed
  // and how big it was: the inspector is built again on every selection
  // and edit, and asks for the material each time.
  static final Map<String, (String, Object?)> _read = {};

  // The material file at [path] (a project path or a package's asset key)
  // parsed by [parse]; null when it is not there. Read again only once it
  // changed.
  T? _file<T extends Object>(String path, T Function(String text) parse) {
    final absolute = PackageAssetPaths.of(_root).absolute(path);
    final stat = FileStat.statSync(absolute);
    if (stat.type == FileSystemEntityType.notFound) return null;
    final stamp = '${stat.modified.microsecondsSinceEpoch}:${stat.size}:$T';
    final known = _read[absolute];
    if (known != null && known.$1 == stamp) return known.$2 as T?;
    final file = parse(File(absolute).readAsStringSync());
    _read[absolute] = (stamp, file);
    return file;
  }

  // ── 2-D ─────────────────────────────────────────────────────────────

  String get _path2D => switch (context.component) {
    final Material2D m => m.material.trim(),
    final ScreenMaterial s => s.material.trim(),
    _ => '',
  };

  /// The 2-D material the component draws with, resolved; null when it
  /// has none or it can't be read.
  Material2DFile? get material2D {
    final path = _path2D;
    if (path.isEmpty) return null;
    try {
      return MaterialChain.resolve2D(
        path,
        (p) => _file(p, Material2DFile.parse),
      ).value;
    } on Object {
      return null;
    }
  }

  // ── 3-D ─────────────────────────────────────────────────────────────

  /// The 3-D material the entity draws with, resolved; null when it has
  /// none or it can't be read.
  MaterialFile? get material3D {
    final world = context.world ?? context.scope?.world;
    final component = context.component;
    if (world == null) return null;
    Entity? owner;
    final selected = context.sceneState?.selectedEntity.value;
    if (selected != null &&
        identical(selected.getComponent<MaterialOverrides3D>(), component)) {
      owner = selected;
    } else {
      for (final e in world.query(const [MaterialOverrides3D])) {
        if (identical(e.getComponent<MaterialOverrides3D>(), component)) {
          owner = e;
          break;
        }
      }
    }
    final path = owner == null ? '' : MaterialSlots.materialOf(owner).trim();
    if (path.isEmpty) return null;
    try {
      return MaterialChain.resolve3D(
        path,
        (p) => _file(p, MaterialFile.parse),
      ).value;
    } on Object {
      return null;
    }
  }

  static const Map<String, String> _labels3D = {
    'color': 'Colour',
    'metallic': 'Metallic',
    'roughness': 'Roughness',
    'emission': 'Glow',
    'emissionStrength': 'Glow strength',
    'opacity': 'Opacity',
    'alphaCutoff': 'Cutoff',
    'normalScale': 'Normal strength',
    'occlusionStrength': 'Occlusion strength',
    'tiling': 'Repeat',
    'offset': 'Shift',
    'rotation': 'Turn',
  };

  /// What [key] edits, and how: its name, kind and range.
  static ({String label, Material2DValue type, double? min, double? max})?
  describe(String key, {required bool flat}) {
    final hash = key.indexOf('#');
    final base = hash < 0 ? key : key.substring(0, hash);
    final axis = hash < 0 ? '' : (key.endsWith('#0') ? ' (across)' : ' (down)');
    if (flat) {
      final found = Material2DEffects.param(base);
      if (found == null) return null;
      final (effect, p) = found;
      if (!p.animatable) return null;
      return (
        label: '${effect.label}: ${p.label}$axis',
        type: hash < 0 ? p.type : Material2DValue.number,
        min: p.min,
        max: p.max,
      );
    }
    final label = _labels3D[base];
    if (label == null) return null;
    final type = switch (base) {
      'color' || 'emission' => Material2DValue.colour,
      'tiling' || 'offset' when hash < 0 => Material2DValue.pair,
      _ => Material2DValue.number,
    };
    final (double? min, double? max) = switch (base) {
      'metallic' ||
      'roughness' ||
      'opacity' ||
      'alphaCutoff' ||
      'occlusionStrength' => (0.0, 1.0),
      'emissionStrength' => (0.0, 20.0),
      'normalScale' => (0.0, 2.0),
      'rotation' => (-180.0, 180.0),
      _ => (null, null),
    };
    return (label: '$label$axis', type: type, min: min, max: max);
  }

  /// The keys that could be added: what the material can change (for a
  /// 2-D one, of the effects it has on), not yet set.
  List<String> get addable {
    final have = values.keys.toSet();
    if (flat) {
      final file = material2D;
      final kind = context.component is ScreenMaterial
          ? Material2DKind.screen
          : Material2DKind.sprite;
      return [
        for (final e in Material2DEffects.forKind(file?.kind ?? kind))
          if (file == null || file.isOn(e.id))
            for (final p in e.params)
              if (p.animatable && !have.contains('${e.id}.${p.name}'))
                '${e.id}.${p.name}',
      ];
    }
    return [
      for (final k in MaterialFile.animatableKeys)
        if (!have.contains(k)) k,
    ];
  }

  /// [key]'s value as the material has it: what an added value starts at.
  Object startOf(String key) {
    if (flat) {
      final file = material2D ?? const Material2DFile();
      return file.valueOf(key);
    }
    final m = material3D ?? const MaterialFile();
    return switch (key) {
      'color' => m.color,
      'metallic' => m.metallic,
      'roughness' => m.roughness,
      'emission' => m.emission,
      'emissionStrength' => m.emissionStrength,
      'opacity' => m.opacity,
      'alphaCutoff' => m.alphaCutoff,
      'normalScale' => m.normalScale,
      'occlusionStrength' => m.occlusionStrength,
      'tiling' => [m.tilingX, m.tilingY],
      'offset' => [m.offsetX, m.offsetY],
      'rotation' => m.rotation,
      _ => 0.0,
    };
  }

  void _set(String key, Object value) =>
      context.onChanged({...values, key: value});

  void _show(String key, Object value) =>
      context.preview?.show({...values, key: value});

  void _remove(String key) => context.onChanged({...values}..remove(key));

  @override
  Widget build(BuildContext build) {
    final current = values;
    final muted = TextStyle(color: EditorTheme.textMuted, fontSize: 11);
    final options = context.readOnly ? const <String>[] : addable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.label, style: InspectorField.labelStyle),
          if (current.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "Drawn with its material's own values. Add one to change it "
                'for this entity alone.',
                style: muted,
              ),
            ),
          for (final MapEntry(:key, :value) in current.entries)
            _row(key, value),
          if (options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: EditorDropdown<String>(
                value: null,
                hint: 'Add a value of its own…',
                searchable: options.length > 8,
                options: [
                  for (final k in options)
                    EditorDropdownOption(
                      value: k,
                      label: describe(k, flat: flat)?.label ?? k,
                    ),
                ],
                onChanged: (k) => _set(k, startOf(k)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String key, Object value) {
    final about = describe(key, flat: flat);
    final label = about?.label ?? key;
    Widget field;
    if (about == null) {
      field = Text(
        "$value — changes nothing",
        style: TextStyle(color: EditorTheme.warning, fontSize: 11),
      );
    } else {
      field = switch (about.type) {
        Material2DValue.colour when value is num => Align(
          alignment: Alignment.centerLeft,
          child: MiniColorField(
            key: ValueKey('$key:$value'),
            color: Color(value.toInt()),
            title: label,
            onPreview: (c) => _show(key, c.toARGB32()),
            onPreviewEnd: () => context.preview?.restore(),
            onChanged: (c) => _set(key, c.toARGB32()),
          ),
        ),
        Material2DValue.pair when value is List && value.length == 2 => Row(
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i == 1) const SizedBox(width: 6),
              Expanded(
                child: MiniNumberField(
                  key: ValueKey('$key#$i:${value[i]}'),
                  value: (value[i] as num).toDouble(),
                  fractionDigits: 2,
                  onSubmitted: (n) {
                    if (!n.isFinite) return;
                    final next = [for (final v in value) (v as num).toDouble()];
                    next[i] = n;
                    _set(key, next);
                  },
                ),
              ),
            ],
          ],
        ),
        _ when value is num && about.min != null && about.max != null =>
          EditorSlider(
            value: value.toDouble().clamp(about.min!, about.max!),
            min: about.min!,
            max: about.max!,
            step: (about.max! - about.min!) / 200,
            decimals: about.max! - about.min! > 20 ? 0 : 2,
            onChanged: (v) => _show(key, v),
            onChangeEnd: (v) {
              context.preview?.restore();
              _set(key, v);
            },
          ),
        _ when value is num => MiniNumberField(
          key: ValueKey('$key:$value'),
          value: value.toDouble(),
          fractionDigits: 2,
          onSubmitted: (n) {
            if (n.isFinite) _set(key, n);
          },
        ),
        _ => Text('$value', style: TextStyle(color: EditorTheme.textMuted)),
      };
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: InspectorField.labelWidth,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: InspectorField.labelStyle,
            ),
          ),
          Expanded(
            child: context.readOnly ? IgnorePointer(child: field) : field,
          ),
          if (!context.readOnly)
            EditorIconButton(
              icon: Icons.close,
              tooltip: "Use the material's own",
              iconSize: 14,
              size: 22,
              onTap: () => _remove(key),
            ),
        ],
      ),
    );
  }
}
