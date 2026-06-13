import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'component_annotations.dart';

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

  bool get isReadOnly => !editable || write == null;

  String get displayLabel => (label == null || label!.isEmpty) ? name : label!;
}

/// Runtime descriptor for one custom component type.
class CustomComponentDescriptor {
  const CustomComponentDescriptor({
    required this.id,
    required this.name,
    required this.type,
    required this.factory,
    required this.fields,
    this.group,
    this.description,
    this.allowMultiple = false,
  });

  final String id;
  final String name;
  final String type;
  final String? group;
  final String? description;
  final bool allowMultiple;
  final jge.Component Function() factory;
  final List<EditorComponentField> fields;
}

/// Global registry consumed by runtime/editor for custom components.
class CustomComponentRegistry {
  CustomComponentRegistry._();

  static final CustomComponentRegistry instance = CustomComponentRegistry._();

  final Map<String, CustomComponentDescriptor> _byId =
      <String, CustomComponentDescriptor>{};
  final Map<String, CustomComponentDescriptor> _byType =
      <String, CustomComponentDescriptor>{};

  List<CustomComponentDescriptor> get descriptors =>
      List<CustomComponentDescriptor>.unmodifiable(_byId.values);

  void clear() {
    _byId.clear();
    _byType.clear();
  }

  void register(CustomComponentDescriptor descriptor) {
    _byId[descriptor.id] = descriptor;
    _byType[descriptor.type] = descriptor;
  }

  void registerAll(Iterable<CustomComponentDescriptor> descriptors) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  CustomComponentDescriptor? descriptorById(String id) => _byId[id];

  CustomComponentDescriptor? descriptorByType(Type type) =>
      _byType[type.toString()];

  CustomComponentDescriptor? descriptorByTypeName(String typeName) =>
      _byType[typeName];

  CustomComponentDescriptor? descriptorForComponent(jge.Component component) =>
      _byType[component.runtimeType.toString()];

  Map<String, dynamic>? componentToJson(jge.Component component) {
    final descriptor = descriptorForComponent(component);
    if (descriptor == null) return null;

    final fieldsJson = <String, dynamic>{};
    for (final field in descriptor.fields) {
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

    for (final field in resolved.fields) {
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
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.boolean:
      case EditorFieldKind.integer:
      case EditorFieldKind.decimal:
      case EditorFieldKind.text:
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
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.boolean:
      case EditorFieldKind.text:
      case EditorFieldKind.unknown:
        return value;
    }
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return 0.0;
  }
}
