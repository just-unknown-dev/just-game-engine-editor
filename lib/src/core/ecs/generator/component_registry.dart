import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// Drag-to-scrub configuration for numeric inspector fields.
class NumberScrubConfig {
  const NumberScrubConfig({
    this.step = 1.0,
    this.pixelsPerStep = 12.0,
    this.fractionDigits = 2,
    this.min,
    this.max,
    this.integer = false,
  });

  final double step;
  final double pixelsPerStep;
  final int fractionDigits;
  final double? min;
  final double? max;
  final bool integer;
}

/// Strongly typed kind used by editor controls and JSON conversion.
enum EditorFieldKind {
  boolean,
  integer,
  decimal,
  text,
  assetRef,
  enumeration,
  list,
  map,
  vector2,
  vector3,
  color,
  offset,
  shapePaintStyle,
  unknown,
}

/// Runtime descriptor for one component property.
class EditorComponentField {
  const EditorComponentField({
    required this.name,
    required this.kind,
    required this.read,
    this.label,
    this.visible = true,
    this.editable = true,
    this.includeInJson = true,
    this.write,
    this.enumValues,
    this.enumParser,
    this.valueFormatter,
    this.scrubConfig,
    this.fileExtensions,
    this.generateTemplate,
  });

  final String name;
  final String? label;
  final EditorFieldKind kind;
  final bool visible;
  final bool editable;
  final bool includeInJson;
  final Object? Function(jge.Component component) read;
  final void Function(jge.Component component, Object? value)? write;
  final List<String>? enumValues;
  final Object? Function(String value)? enumParser;
  final String Function(Object? value)? valueFormatter;
  final NumberScrubConfig? scrubConfig;
  /// For [EditorFieldKind.assetRef]: restricts the file picker to these extensions
  /// (without the leading dot, e.g. `['png', 'jpg']`). Defaults to `['png']`.
  final List<String>? fileExtensions;
  /// For [EditorFieldKind.assetRef]: when set, shows a generate button that
  /// calls this callback. Returns the written file path on success, or null.
  final Future<String?> Function(jge.Component component)? generateTemplate;

  bool get isReadOnly => !editable || write == null;

  String get displayLabel => (label == null || label!.isEmpty) ? name : label!;
}

/// A named group of fields shown as a sub-section inside the inspector.
class EditorFieldGroup {
  const EditorFieldGroup({required this.name, required this.fields});

  final String name;
  final List<EditorComponentField> fields;
}

enum ComponentType {
  /// Wraps a component from the game engine package.
  core,

  /// Defined inside the editor package itself.
  editor,

  /// Reserved for future use.
  experimental,
}

/// Runtime descriptor for one component type.
class EditorComponent {
  const EditorComponent({
    required this.id,
    required this.name,
    required this.type,
    required this.factory,
    this.fields = const [],
    this.fieldGroups,
    this.group,
    this.description,
    this.allowMultiple = false,
    this.deletable = true,
    this.componentType = ComponentType.core,
    this.icon,
    this.accentColor,
  });

  final String id;
  final String name;
  final String type;
  final String? group;
  final String? description;
  final bool allowMultiple;
  final bool deletable;
  final ComponentType componentType;
  final jge.Component Function() factory;

  /// Flat field list — used directly when [fieldGroups] is null.
  final List<EditorComponentField> fields;

  /// Optional sub-groups; when set the inspector renders a header per group.
  final List<EditorFieldGroup>? fieldGroups;

  /// Icon shown in the component picker row and inspector header.
  final IconData? icon;

  /// Accent colour applied to the inspector header bar.
  final Color? accentColor;

  /// All fields flattened: direct [fields] + all fields from [fieldGroups].
  List<EditorComponentField> get allFields => [
    ...fields,
    if (fieldGroups != null)
      for (final g in fieldGroups!) ...g.fields,
  ];
}

/// Global registry consumed by runtime/editor for component descriptors.
class CustomComponentRegistry {
  CustomComponentRegistry._();

  static final CustomComponentRegistry instance = CustomComponentRegistry._();

  final Map<String, EditorComponent> _byId = <String, EditorComponent>{};
  final Map<String, EditorComponent> _byType = <String, EditorComponent>{};

  List<EditorComponent> get descriptors =>
      List<EditorComponent>.unmodifiable(_byId.values);

  void clear() {
    _byId.clear();
    _byType.clear();
  }

  void register(EditorComponent descriptor) {
    _byId[descriptor.id] = descriptor;
    _byType[descriptor.type] = descriptor;
  }

  void registerAll(Iterable<EditorComponent> descriptors) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  EditorComponent? descriptorById(String id) => _byId[id];

  EditorComponent? descriptorByType(Type type) => _byType[type.toString()];

  EditorComponent? descriptorByTypeName(String typeName) => _byType[typeName];

  EditorComponent? descriptorForComponent(jge.Component component) =>
      _byType[component.runtimeType.toString()];

  Map<String, dynamic>? componentToJson(jge.Component component) {
    final descriptor = descriptorForComponent(component);
    if (descriptor == null) return null;

    final fieldsJson = <String, dynamic>{};
    for (final field in descriptor.allFields) {
      if (!field.includeInJson) continue;
      final rawValue = field.read(component);
      fieldsJson[field.name] = _encodeValue(field, rawValue);
    }

    return <String, dynamic>{
      'type': descriptor.type,
      'customComponentId': descriptor.id,
      'fields': fieldsJson,
    };
  }

  jge.Component? componentFromJson(Map<String, dynamic> json) {
    final id = json['customComponentId'] as String?;
    final type = json['type'] as String?;
    final descriptor = (id != null) ? _byId[id] : null;
    final resolved = descriptor ?? ((type != null) ? _byType[type] : null);
    if (resolved == null) return null;

    final component = resolved.factory();
    final fieldsJson =
        (json['fields'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    for (final field in resolved.allFields) {
      final writer = field.write;
      if (writer == null) continue;
      if (!fieldsJson.containsKey(field.name)) continue;
      writer(component, _decodeValue(field, fieldsJson[field.name]));
    }
    return component;
  }

  static dynamic _encodeValue(EditorComponentField field, Object? value) {
    if (value == null) return null;

    switch (field.kind) {
      case EditorFieldKind.color:
        if (value is Color) return value.toARGB32();
        return value;
      case EditorFieldKind.offset:
        if (value is Offset) {
          return <String, dynamic>{'dx': value.dx, 'dy': value.dy};
        }
        return value;
      case EditorFieldKind.vector2:
        if (value is jge.Vector2) {
          return <String, dynamic>{'x': value.x, 'y': value.y};
        }
        return value;
      case EditorFieldKind.vector3:
        if (value is jge.Vector3) {
          return <String, dynamic>{'x': value.x, 'y': value.y, 'z': value.z};
        }
        return value;
      case EditorFieldKind.enumeration:
        return value.toString().split('.').last;
      case EditorFieldKind.shapePaintStyle:
        if (value is jge.ShapePaintStyle) {
          final g = value.gradient;
          return <String, dynamic>{
            'color': value.color.toARGB32(),
            if (g != null)
              'gradient': <String, dynamic>{
                'kind': g.kind.name,
                'colors': g.colors.map((c) => c.toARGB32()).toList(),
                if (g.stops != null) 'stops': g.stops,
                'beginX': g.begin is Alignment
                    ? (g.begin as Alignment).x
                    : -1.0,
                'beginY': g.begin is Alignment ? (g.begin as Alignment).y : 0.0,
                'endX': g.end is Alignment ? (g.end as Alignment).x : 1.0,
                'endY': g.end is Alignment ? (g.end as Alignment).y : 0.0,
                'centerX': g.center is Alignment
                    ? (g.center as Alignment).x
                    : 0.0,
                'centerY': g.center is Alignment
                    ? (g.center as Alignment).y
                    : 0.0,
                'radius': g.radius,
                'startAngle': g.startAngle,
                'endAngle': g.endAngle,
                'tileMode': g.tileMode.index,
              },
          };
        }
        return value;
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.boolean:
      case EditorFieldKind.integer:
      case EditorFieldKind.decimal:
      case EditorFieldKind.text:
      case EditorFieldKind.assetRef:
      case EditorFieldKind.unknown:
        return value;
    }
  }

  static Object? _decodeValue(EditorComponentField field, dynamic value) {
    if (value == null) return null;

    switch (field.kind) {
      case EditorFieldKind.color:
        if (value is int) return Color(value);
        return value;
      case EditorFieldKind.offset:
        if (value is Map) {
          return Offset(_toDouble(value['dx']), _toDouble(value['dy']));
        }
        return value;
      case EditorFieldKind.vector2:
        if (value is Map) {
          return jge.Vector2(_toDouble(value['x']), _toDouble(value['y']));
        }
        return value;
      case EditorFieldKind.vector3:
        if (value is Map) {
          return jge.Vector3(
            _toDouble(value['x']),
            _toDouble(value['y']),
            _toDouble(value['z']),
          );
        }
        return value;
      case EditorFieldKind.enumeration:
        if (value is String) {
          return field.enumParser != null ? field.enumParser!(value) : value;
        }
        return value;
      case EditorFieldKind.integer:
        if (value is num) return value.toInt();
        return value;
      case EditorFieldKind.decimal:
        if (value is num) return value.toDouble();
        return value;
      case EditorFieldKind.shapePaintStyle:
        if (value is Map) {
          final m = value.cast<String, dynamic>();
          final color = Color((m['color'] as num?)?.toInt() ?? 0xFFFFFFFF);
          final gMap = m['gradient'] as Map<String, dynamic>?;
          if (gMap == null) return jge.ShapePaintStyle(color: color);
          final kindName = gMap['kind'] as String? ?? 'linear';
          final kind = jge.ShapeGradientKind.values.firstWhere(
            (k) => k.name == kindName,
            orElse: () => jge.ShapeGradientKind.linear,
          );
          final colors = ((gMap['colors'] as List?)?.cast<dynamic>() ?? [])
              .map((e) => Color((e as num).toInt()))
              .toList();
          final stops = (gMap['stops'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList();
          final tileIdx = (gMap['tileMode'] as num?)?.toInt() ?? 0;
          final tileMode =
              TileMode.values[tileIdx.clamp(0, TileMode.values.length - 1)];
          jge.ShapeGradient gradient;
          switch (kind) {
            case jge.ShapeGradientKind.linear:
              gradient = jge.ShapeGradient.linear(
                colors: colors.isEmpty ? [color] : colors,
                stops: stops,
                begin: Alignment(
                  _toDouble(gMap['beginX']),
                  _toDouble(gMap['beginY']),
                ),
                end: Alignment(
                  _toDouble(gMap['endX'] ?? 1.0),
                  _toDouble(gMap['endY']),
                ),
                tileMode: tileMode,
              );
            case jge.ShapeGradientKind.radial:
              gradient = jge.ShapeGradient.radial(
                colors: colors.isEmpty ? [color] : colors,
                stops: stops,
                center: Alignment(
                  _toDouble(gMap['centerX']),
                  _toDouble(gMap['centerY']),
                ),
                radius: _toDouble(gMap['radius'] ?? 0.5),
                tileMode: tileMode,
              );
            case jge.ShapeGradientKind.sweep:
              gradient = jge.ShapeGradient.sweep(
                colors: colors.isEmpty ? [color] : colors,
                stops: stops,
                center: Alignment(
                  _toDouble(gMap['centerX']),
                  _toDouble(gMap['centerY']),
                ),
                startAngle: _toDouble(gMap['startAngle']),
                endAngle: _toDouble(gMap['endAngle'] ?? 6.283185307),
                tileMode: tileMode,
              );
          }
          return jge.ShapePaintStyle(color: color, gradient: gradient);
        }
        return value;
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.boolean:
      case EditorFieldKind.text:
      case EditorFieldKind.assetRef:
      case EditorFieldKind.unknown:
        return value;
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return 0.0;
  }
}
