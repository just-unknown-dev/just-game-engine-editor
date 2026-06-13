import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/ecs/generator/component_annotations.dart';
import '../../core/ecs/generator/component_registry.dart';
import '../../core/state/editor_scene_state.dart';
import '../theme/editor_theme.dart';

List<Widget> buildCustomComponentSections({
  required jge.Entity entity,
  required EditorSceneState sceneState,
}) {
  final sections = <Widget>[];
  for (final component in entity.components) {
    final descriptor = CustomComponentRegistry.instance.descriptorForComponent(
      component,
    );
    if (descriptor == null) continue;

    sections.add(
      CustomComponentSection(
        component: component,
        descriptor: descriptor,
        onDelete: () {
          entity.removeComponentByType(component.componentType);
          sceneState.markDirty();
          sceneState.refresh();
        },
        onChanged: () {
          sceneState.markDirty();
          sceneState.refresh();
        },
      ),
    );
  }
  return sections;
}

class CustomComponentSection extends StatelessWidget {
  const CustomComponentSection({
    super.key,
    required this.component,
    required this.descriptor,
    required this.onDelete,
    required this.onChanged,
  });

  final jge.Component component;
  final CustomComponentDescriptor descriptor;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final visibleFields = descriptor.fields.where((f) => f.visible).toList();

    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EditorTheme.border),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  descriptor.name,
                  style: const TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: EditorTheme.textMuted,
                ),
              ),
            ],
          ),
          if (descriptor.description != null &&
              descriptor.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                descriptor.description!,
                style: const TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            )
          else
            const SizedBox(height: 8),
          if (visibleFields.isEmpty)
            const Text(
              'No visible properties',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
            )
          else
            ...visibleFields.map((field) {
              final value = field.read(component);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _EditorFieldControl(
                  label: field.displayLabel,
                  field: field,
                  value: value,
                  onChanged: (next) {
                    final writer = field.write;
                    if (writer == null) return;
                    writer(component, next);
                    onChanged();
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _EditorFieldControl extends StatelessWidget {
  const _EditorFieldControl({
    required this.label,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final EditorComponentField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.isReadOnly) {
      return _ReadonlyRow(label: label, value: _displayValue(field, value));
    }

    switch (field.kind) {
      case EditorFieldKind.boolean:
        return _BoolEditorRow(
          label: label,
          value: value == true,
          onChanged: (v) => onChanged(v),
        );
      case EditorFieldKind.enumeration:
        final options = field.enumValues ?? const <String>[];
        final selected = _enumSelectedValue(value);
        if (options.isEmpty) {
          return _ReadonlyRow(label: label, value: _displayValue(field, value));
        }
        return _DropdownEditorRow(
          label: label,
          value: options.contains(selected) ? selected : options.first,
          options: options,
          onChanged: (next) {
            if (field.enumParser != null) {
              onChanged(field.enumParser!(next));
            } else {
              onChanged(next);
            }
          },
        );
      case EditorFieldKind.integer:
      case EditorFieldKind.decimal:
      case EditorFieldKind.text:
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.vector2:
      case EditorFieldKind.vector3:
      case EditorFieldKind.color:
      case EditorFieldKind.offset:
      case EditorFieldKind.unknown:
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = _parseTextValue(field, text, previous: value);
            if (parsed != null || field.kind == EditorFieldKind.text) {
              onChanged(parsed);
            }
          },
        );
    }
  }

  static String _enumSelectedValue(Object? value) {
    if (value == null) return '';
    final raw = value.toString();
    if (raw.contains('.')) {
      return raw.split('.').last;
    }
    return raw;
  }

  static String _displayValue(EditorComponentField field, Object? value) {
    if (field.valueFormatter != null) return field.valueFormatter!(value);
    if (value == null) return '';

    switch (field.kind) {
      case EditorFieldKind.list:
      case EditorFieldKind.map:
        return const JsonEncoder.withIndent('  ').convert(value);
      case EditorFieldKind.vector2:
        if (value is jge.Vector2) return '${value.x}, ${value.y}';
        return value.toString();
      case EditorFieldKind.vector3:
        if (value is jge.Vector3) return '${value.x}, ${value.y}, ${value.z}';
        return value.toString();
      case EditorFieldKind.offset:
        if (value is Offset) return '${value.dx}, ${value.dy}';
        return value.toString();
      case EditorFieldKind.color:
        if (value is Color) {
          final hex = value.toARGB32().toRadixString(16).padLeft(8, '0');
          return '#${hex.toUpperCase()}';
        }
        return value.toString();
      case EditorFieldKind.boolean:
      case EditorFieldKind.integer:
      case EditorFieldKind.decimal:
      case EditorFieldKind.text:
      case EditorFieldKind.enumeration:
      case EditorFieldKind.unknown:
        return value.toString();
    }
  }

  static Object? _parseTextValue(
    EditorComponentField field,
    String text, {
    required Object? previous,
  }) {
    final raw = text.trim();
    switch (field.kind) {
      case EditorFieldKind.integer:
        return int.tryParse(raw) ?? previous;
      case EditorFieldKind.decimal:
        return double.tryParse(raw) ?? previous;
      case EditorFieldKind.text:
        return raw;
      case EditorFieldKind.list:
        try {
          final decoded = jsonDecode(raw);
          return (decoded is List) ? decoded : previous;
        } catch (_) {
          return previous;
        }
      case EditorFieldKind.map:
        try {
          final decoded = jsonDecode(raw);
          return (decoded is Map) ? decoded.cast<String, dynamic>() : previous;
        } catch (_) {
          return previous;
        }
      case EditorFieldKind.vector2:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 2) return previous;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x == null || y == null) return previous;
        return jge.Vector2(x, y);
      case EditorFieldKind.vector3:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 3) return previous;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        final z = double.tryParse(parts[2]);
        if (x == null || y == null || z == null) return previous;
        return jge.Vector3(x, y, z);
      case EditorFieldKind.offset:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 2) return previous;
        final dx = double.tryParse(parts[0]);
        final dy = double.tryParse(parts[1]);
        if (dx == null || dy == null) return previous;
        return Offset(dx, dy);
      case EditorFieldKind.color:
        final normalized = raw.replaceFirst('#', '');
        final argb = int.tryParse(normalized, radix: 16);
        if (argb == null) return previous;
        return Color(argb);
      case EditorFieldKind.boolean:
      case EditorFieldKind.enumeration:
      case EditorFieldKind.unknown:
        return previous;
    }
  }
}

class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _BoolEditorRow extends StatelessWidget {
  const _BoolEditorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: EditorTheme.primary,
        ),
      ],
    );
  }
}

class _TextEditorRow extends StatelessWidget {
  const _TextEditorRow({
    required this.label,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              label,
              style: const TextStyle(
                color: EditorTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            initialValue: initialValue,
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
            ),
            minLines: 1,
            maxLines: 4,
            onFieldSubmitted: onSubmitted,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              filled: true,
              fillColor: EditorTheme.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.primaryActive),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownEditorRow extends StatelessWidget {
  const _DropdownEditorRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: EditorTheme.inputBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EditorTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: EditorTheme.dialogBg,
                style: const TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 11,
                ),
                items: options
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
