import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/ecs/generator/component_annotations.dart';
import '../../core/ecs/generator/component_registry.dart';
import '../../core/services/component_codegen_runner.dart';
import '../../core/services/component_source_index.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import '../../core/services/editor_log_service.dart';
import '../../core/state/editor_scene_state.dart';
import '../theme/editor_theme.dart';
import '../widgets/scrubbable_number_field.dart';

List<Widget> buildCustomComponentSections({
  required jge.Entity entity,
  required EditorSceneState sceneState,
}) {
  final sections = <Widget>[];
  for (final component in entity.components) {
    final typeName = component.runtimeType.toString();
    final descriptor = CustomComponentRegistry.instance.descriptorForComponent(
      component,
    );

    if (descriptor == null) {
      // No descriptor — show skeleton if code gen is in progress for this type.
      if (sceneState.isCodegenInProgress(typeName)) {
        sections.add(_SkeletonSection(typeName: typeName));
      }
      continue;
    }

    final codegenInProgress = sceneState.isCodegenInProgress(descriptor.type);

    // _sourcePathByType is keyed by the EditorComponent class name, not the
    // base type name. Derive it: 'HealthPowerupComponent' →
    // 'HealthPowerupEditorComponent'. Fall back to direct lookup for cases
    // where the class name matches (e.g. non-editor custom components).
    final editorClassName = descriptor.type.endsWith('Component')
        ? descriptor.type.replaceFirst('Component', 'EditorComponent')
        : null;
    final sourcePath =
        (editorClassName != null
            ? ComponentSourceIndex.instance.sourcePathForType(editorClassName)
            : null) ??
        ComponentSourceIndex.instance.sourcePathForType(descriptor.type);

    // Reload is only meaningful for project-level custom components — not for
    // core or editor-package components whose .jge.dart files are static.
    // For debug builds, allow reload for all components to support rapid iteration.
    final isReloadable =
        (kDebugMode || descriptor.componentType == ComponentType.custom) &&
        sourcePath != null;

    sections.add(
      CustomComponentSection(
        component: component,
        descriptor: descriptor,
        codegenInProgress: codegenInProgress,
        onDelete: () {
          entity.removeComponentByType(component.componentType);
          sceneState.markDirty();
          sceneState.refresh();
        },
        onChanged: () {
          sceneState.syncEntityNode(entity);
          sceneState.markDirty();
          sceneState.refresh();
        },
        onReload: isReloadable
            ? () => _triggerSectionCodegen(
                sourcePath: sourcePath,
                typeName: descriptor.type,
                componentName: descriptor.name,
                sceneState: sceneState,
              )
            : null,
      ),
    );
  }
  return sections;
}

void _triggerSectionCodegen({
  required String sourcePath,
  required String typeName,
  required String componentName,
  required EditorSceneState sceneState,
}) {
  if (sceneState.isCodegenInProgress(typeName)) return;
  sceneState.startCodegen(typeName);

  final log = EditorLogService.instance;
  final stopwatch = Stopwatch()..start();
  final outputBuffer = StringBuffer();

  log.log(
    'Regenerating "$componentName" ($typeName)…',
    source: 'codegen',
    category: 'generate-one',
  );

  runComponentGenerateOne(
    sourcePath,
    editorScope: true,
    onLog: (line) {
      log.logProcessChunk(line);
      outputBuffer.writeln(line);
    },
  ).then((result) {
    stopwatch.stop();
    final ms = stopwatch.elapsedMilliseconds;

    if (result.success) {
      log.log(
        '"$componentName" code gen completed in ${ms}ms.',
        source: 'codegen',
        category: 'generate-one',
        details: outputBuffer.isNotEmpty ? outputBuffer.toString().trim() : null,
      );
    } else {
      log.log(
        '"$componentName" code gen failed after ${ms}ms.',
        source: 'codegen',
        category: 'generate-one',
        level: DebuggerLogLevel.error,
        details: outputBuffer.isNotEmpty
            ? outputBuffer.toString().trim()
            : result.output,
      );
    }
    sceneState.reloadCustomComponents();
  }).whenComplete(() {
    sceneState.finishCodegen(typeName);
  });
}

class CustomComponentSection extends StatelessWidget {
  const CustomComponentSection({
    super.key,
    required this.component,
    required this.descriptor,
    required this.onDelete,
    required this.onChanged,
    this.codegenInProgress = false,
    this.onReload,
  });

  final jge.Component component;
  final EditorComponentDescriptor descriptor;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  /// True while background code gen is running for this component type.
  final bool codegenInProgress;

  /// Triggers a targeted code gen re-run for this component's source file.
  /// Null when no source path is available (e.g. core/editor components).
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final visibleFields = descriptor.fields.where((f) => f.visible).toList();

    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Text(
                  descriptor.name,
                  style: const TextStyle(
                    color: EditorTheme.primaryMutedLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                _ComponentTag(componentType: descriptor.componentType),
                const Spacer(),
                if (onReload != null)
                  GestureDetector(
                    onTap: codegenInProgress ? null : onReload,
                    child: Icon(
                      Icons.refresh_rounded,
                      size: 14,
                      color: codegenInProgress
                          ? EditorTheme.textMuted.withValues(alpha: 0.4)
                          : EditorTheme.textMuted,
                    ),
                  ),
                if (onReload != null && descriptor.deletable)
                  const SizedBox(width: 6),
                if (descriptor.deletable)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          // Divider becomes a thin progress bar while code gen is running.
          if (codegenInProgress)
            const LinearProgressIndicator(
              minHeight: 1,
              backgroundColor: EditorTheme.border,
              valueColor: AlwaysStoppedAnimation<Color>(EditorTheme.primary),
            )
          else
            const Divider(height: 1, color: EditorTheme.border),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (descriptor.description != null &&
                    descriptor.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      descriptor.description!,
                      style: const TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (visibleFields.isEmpty)
                  const Text(
                    'No visible properties',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 11,
                    ),
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
          ),
        ],
      ),
    );
  }
}

// ── Skeleton section (shown while first-time codegen is pending) ──────────────

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection({required this.typeName});

  final String typeName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Text(
                  typeName,
                  style: const TextStyle(
                    color: EditorTheme.primaryMutedLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      EditorTheme.primaryMutedLight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const LinearProgressIndicator(
            minHeight: 1,
            backgroundColor: EditorTheme.border,
            valueColor: AlwaysStoppedAnimation<Color>(EditorTheme.primary),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(
                3,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: EditorTheme.border.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    width: i == 2 ? 80 : double.infinity,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _ComponentTag extends StatelessWidget {
  const _ComponentTag({required this.componentType});

  final ComponentType componentType;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, border) = switch (componentType) {
      ComponentType.core => (
        'CORE',
        EditorTheme.primaryMutedLight,
        EditorTheme.primaryMuted.withValues(alpha: 0.18),
        EditorTheme.primaryMuted.withValues(alpha: 0.5),
      ),
      ComponentType.editor => (
        'EDITOR',
        const Color(0xFF81C9E8),
        const Color(0xFF81C9E8).withValues(alpha: 0.12),
        const Color(0xFF81C9E8).withValues(alpha: 0.45),
      ),
      ComponentType.experimental => (
        'EXP',
        const Color(0xFFE8C47A),
        const Color(0xFFE8C47A).withValues(alpha: 0.12),
        const Color(0xFFE8C47A).withValues(alpha: 0.45),
      ),
      ComponentType.custom => (
        'CUSTOM',
        EditorTheme.textMuted,
        EditorTheme.surfaceDark,
        EditorTheme.border,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Field control dispatcher ──────────────────────────────────────────────────

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
      case EditorFieldKind.decimal:
        if (field.scrubConfig != null) {
          return _ScrubFieldRow(
            label: label,
            value: (value as num?)?.toDouble() ?? 0.0,
            scrubConfig: field.scrubConfig!,
            onChanged: (v) => onChanged(v),
          );
        }
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = double.tryParse(text.trim());
            if (parsed != null) onChanged(parsed);
          },
        );
      case EditorFieldKind.integer:
        if (field.scrubConfig != null) {
          return _ScrubFieldRow(
            label: label,
            value: (value as num?)?.toDouble() ?? 0.0,
            scrubConfig: field.scrubConfig!,
            onChanged: (v) =>
                onChanged(field.scrubConfig!.integer ? v.round() : v),
          );
        }
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) onChanged(parsed);
          },
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
    if (raw.contains('.')) return raw.split('.').last;
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
        if (value is jge.Vector3) {
          return '${value.x}, ${value.y}, ${value.z}';
        }
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

// ── Row widgets ───────────────────────────────────────────────────────────────

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
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: EditorTheme.primaryMutedLight,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: EditorTheme.border),
          ),
        ),
      ],
    );
  }
}

/// Stateful row that owns its controller/focus and supports drag-scrub.
class _ScrubFieldRow extends StatefulWidget {
  const _ScrubFieldRow({
    required this.label,
    required this.value,
    required this.scrubConfig,
    required this.onChanged,
  });

  final String label;
  final double value;
  final NumberScrubConfig scrubConfig;
  final ValueChanged<double> onChanged;

  @override
  State<_ScrubFieldRow> createState() => _ScrubFieldRowState();
}

class _ScrubFieldRowState extends State<_ScrubFieldRow> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(_ScrubFieldRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (widget.scrubConfig.integer) return v.round().toString();
    return v.toStringAsFixed(widget.scrubConfig.fractionDigits);
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v != null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return ScrubbableNumberField(
      label: widget.label,
      controller: _ctrl,
      focusNode: _focus,
      onCommit: _commit,
      config: widget.scrubConfig,
      labelWidth: 96,
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
