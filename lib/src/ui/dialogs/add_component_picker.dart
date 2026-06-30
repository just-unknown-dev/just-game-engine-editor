import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart' hide Animation;
import '../theme/editor_theme.dart';
import '../overlay/editor_overlay.dart'
    show
        EditorSnackBarEntry,
        EditorMessenger,
        EditorSnackBarStep,
        EditorSnackBarType;

import '../../core/ecs/registry/component_registry.dart';
import '../../core/ecs/generator/component_registry.dart';
import '../../core/services/component_codegen_runner.dart';
import '../../core/services/component_indexing_service.dart';
import '../../core/services/editor_log_service.dart';
import '../../core/state/editor_scene_state.dart';

/// An expandable in-place panel that lets the user search for and add a
/// component to the currently selected entity.
///
/// Place this at the bottom of the inspector.  It expands downward when the
/// user taps "+ Add Component".
class AddComponentPicker extends StatefulWidget {
  const AddComponentPicker({
    super.key,
    required this.entity,
    required this.sceneState,
  });

  final Entity entity;
  final EditorSceneState sceneState;

  @override
  State<AddComponentPicker> createState() => _AddComponentPickerState();
}

class _AddComponentPickerState extends State<AddComponentPicker>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _isRefreshing = false;
  bool _didScheduleInitialRefresh = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  late final AnimationController _animCtrl;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _heightFactor = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.toLowerCase());
    });

    ComponentIndexingService.instance.addListener(_onBackgroundIndexRefreshed);
  }

  @override
  void dispose() {
    ComponentIndexingService.instance.removeListener(
      _onBackgroundIndexRefreshed,
    );
    _animCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onBackgroundIndexRefreshed() {
    if (!mounted) return;
    widget.sceneState.reloadCustomComponents();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
      // Start/refresh background indexing while picker is open.
      ComponentIndexingService.instance.scheduleRefresh();
      _didScheduleInitialRefresh = true;
    } else {
      _animCtrl.reverse();
      _searchCtrl.clear();
    }
  }

  /// Returns the runtime types of components already attached to the entity so
  /// we can grey out duplicates.
  Set<String> get _existingTypes =>
      widget.entity.components.map((c) => c.runtimeType.toString()).toSet();

  List<ComponentEntry> get _filtered {
    final allEntries = getComponentRegistryEntries();
    if (_query.isEmpty) return allEntries;
    return allEntries
        .where(
          (e) =>
              e.name.toLowerCase().contains(_query) ||
              e.group.toLowerCase().contains(_query) ||
              e.description.toLowerCase().contains(_query),
        )
        .toList();
  }

  /// True when this entry should trigger background code gen after adding:
  /// only project-level custom components (not editor-package ones).
  bool _needsBackgroundCodegen(ComponentEntry entry) =>
      entry.isCustom && !entry.isEditorComponent && entry.sourcePath != null;

  /// Resolves the descriptor for a custom entry, trying both the entry's
  /// componentTypeName and the EditorComponent → base-type fallback.
  EditorComponentDescriptor? _resolveDescriptor(ComponentEntry entry) {
    final typeName = entry.componentTypeName;
    if (typeName == null) return null;
    var descriptor =
        CustomComponentRegistry.instance.descriptorByTypeName(typeName);
    if (descriptor == null && typeName.endsWith('EditorComponent')) {
      final base = typeName.replaceFirst('EditorComponent', 'Component');
      descriptor = CustomComponentRegistry.instance.descriptorByTypeName(base);
    }
    return descriptor;
  }

  Future<void> _addComponent(ComponentEntry entry) async {
    // Determine whether a descriptor (and therefore a factory) is available.
    final descriptor = _needsBackgroundCodegen(entry)
        ? _resolveDescriptor(entry)
        : null;
    final hasDescriptor = !_needsBackgroundCodegen(entry) || descriptor != null;

    if (_needsBackgroundCodegen(entry) && !hasDescriptor) {
      // ── First-time add: no descriptor yet. Run generation synchronously,
      //    then add the component once the factory is available. ──
      final log = EditorLogService.instance;
      final stopwatch = Stopwatch()..start();
      final outputBuffer = StringBuffer();

      log.log(
        'Generating "${entry.name}" for first-time add…',
        source: 'codegen',
        category: 'generate-one',
      );

      final result = await runComponentGenerateOne(
        entry.sourcePath!,
        editorScope: entry.isEditorComponent,
        onLog: (line) {
          log.logProcessChunk(line);
          outputBuffer.writeln(line);
        },
      );
      if (!mounted) return;

      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;

      if (!result.success) {
        log.log(
          '"${entry.name}" code gen failed after ${ms}ms.',
          source: 'codegen',
          category: 'generate-one',
          level: DebuggerLogLevel.error,
          details: outputBuffer.isNotEmpty
              ? outputBuffer.toString().trim()
              : result.output,
        );
        EditorMessenger.of(context).showSnackBar(
          EditorSnackBarEntry(
            message: 'Component generation failed: ${result.output}',
            type: EditorSnackBarType.error,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      log.log(
        '"${entry.name}" code gen completed in ${ms}ms.',
        source: 'codegen',
        category: 'generate-one',
        details: outputBuffer.isNotEmpty ? outputBuffer.toString().trim() : null,
      );
      // Write/update the project-level registrant so the new .jge.dart
      // self-registers on the next hot-reload.
      final jgePath = entry.sourcePath!.replaceFirst('.dart', '.jge.dart');
      final registrantPath = _writeProjectRegistrant(jgePath);

      widget.sceneState.reloadCustomComponents();
      final refreshed = _resolveDescriptor(entry);
      if (refreshed == null) {
        final hint = registrantPath != null
            ? 'Registrant written to:\n  $registrantPath\n\n'
                'ONE-TIME SETUP — add ONE import to your app (e.g. main.dart):\n\n'
                "  import '<path>/generated_component_registrant.dart';\n\n"
                'No function calls needed. Importing the file is enough.\n'
                'After that, every new component is auto-registered on hot-reload.'
            : 'Expected type: ${entry.componentTypeName ?? "(unknown)"}\n'
                'Registered: ${CustomComponentRegistry.instance.descriptors.map((d) => d.type).join(", ")}';
        log.log(
          '"${entry.name}" descriptor unavailable — hot-reload required.',
          source: 'codegen',
          category: 'generate-one',
          level: DebuggerLogLevel.warning,
          details: hint,
        );
        EditorMessenger.of(context).showSnackBar(
          const EditorSnackBarEntry(
            message: 'Generated! Hot-reload to register the new component.',
            type: EditorSnackBarType.warning,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      widget.entity.addComponent(refreshed.factory());
      widget.sceneState.markDirty();
      widget.sceneState.refresh();
      _toggle();
      return;
    }

    // ── Normal add: factory is available. Add immediately. ──
    widget.entity.addComponent(entry.factory());
    widget.sceneState.markDirty();
    widget.sceneState.refresh();
    _toggle();

    // ── Background codegen for custom project components that already have a
    //    descriptor — re-generate to pick up any source changes. The inspector
    //    shows a progress bar on the new section while gen runs. ──
    if (_needsBackgroundCodegen(entry)) {
      final codegenType = descriptor?.type ?? entry.componentTypeName ?? '';
      widget.sceneState.startCodegen(codegenType);
      _runBackgroundCodegen(entry, codegenType);
    }
  }

  void _runBackgroundCodegen(ComponentEntry entry, String codegenType) {
    final log = EditorLogService.instance;
    final stopwatch = Stopwatch()..start();
    final outputBuffer = StringBuffer();

    log.log(
      'Regenerating "${entry.name}" in the background…',
      source: 'codegen',
      category: 'generate-one',
    );

    runComponentGenerateOne(
      entry.sourcePath!,
      editorScope: entry.isEditorComponent,
      onLog: (line) {
        log.logProcessChunk(line);
        outputBuffer.writeln(line);
      },
    ).then((result) {
      if (!mounted) return;
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;

      if (result.success) {
        log.log(
          '"${entry.name}" background code gen completed in ${ms}ms.',
          source: 'codegen',
          category: 'generate-one',
          details:
              outputBuffer.isNotEmpty ? outputBuffer.toString().trim() : null,
        );
      } else {
        log.log(
          '"${entry.name}" background code gen failed after ${ms}ms.',
          source: 'codegen',
          category: 'generate-one',
          level: DebuggerLogLevel.error,
          details: outputBuffer.isNotEmpty
              ? outputBuffer.toString().trim()
              : result.output,
        );
      }
      widget.sceneState.reloadCustomComponents();
    }).whenComplete(() {
      if (mounted) widget.sceneState.finishCodegen(codegenType);
    });
  }

  /// Writes (or updates) a `generated_component_registrant.dart` file in the
  /// same directory as [jgeDartPath]. It imports every
  /// `*_editor_component.jge.dart` sibling and exposes a single
  /// `registerCustomComponents()` function.
  ///
  /// Returns the path of the written file, or null on failure.
  String? _writeProjectRegistrant(String jgeDartPath) {
    try {
      final dir = p.dirname(jgeDartPath);
      final jgeFiles = Directory(dir)
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                p.basename(f.path).endsWith('_editor_component.jge.dart') &&
                !p.basename(f.path).startsWith('generated_component_registrant'),
          )
          .toList()
        ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

      if (jgeFiles.isEmpty) return null;

      final buf = StringBuffer()
        ..writeln(
          '// AUTO-GENERATED by just_game_engine_editor — do not modify.',
        )
        ..writeln('// Re-generated whenever a custom component is added.')
        ..writeln('// ignore_for_file: type=lint, unused_import')
        ..writeln()
        ..writeln('// ── ONE-TIME SETUP ──────────────────────────────────')
        ..writeln('//')
        ..writeln('// Add ONE import to your app startup (e.g. main.dart):')
        ..writeln('//')
        ..writeln("// import 'path/to/this/generated_component_registrant.dart';")
        ..writeln('//')
        ..writeln('// That is ALL. No function calls needed.')
        ..writeln('// Each component self-registers the moment this file')
        ..writeln('// is imported. Every new component added after that')
        ..writeln('// is automatically included here and registered on')
        ..writeln('// the next hot-reload.')
        ..writeln('// ─────────────────────────────────────────────────────')
        ..writeln();

      // Each .jge.dart file self-registers when imported (via _$registered).
      // Importing this registrant is ALL that's needed — no function call.
      for (var i = 0; i < jgeFiles.length; i++) {
        final name = p.basename(jgeFiles[i].path);
        buf.writeln("import '$name';  // self-registers on import");
      }

      // Named function kept for backward compatibility and explicit use.
      buf
        ..writeln()
        ..writeln(
          '/// Registers all project custom component descriptors.',
        )
        ..writeln('/// Importing this file is sufficient — this function')
        ..writeln('/// is provided only for explicit/legacy call sites.')
        ..writeln('void registerCustomComponents([dynamic registry]) {')
        ..writeln('  // Registration already happened on import.')
        ..writeln('}');

      final registrantPath =
          p.join(dir, 'generated_component_registrant.dart');
      File(registrantPath).writeAsStringSync(buf.toString());
      return registrantPath;
    } catch (e) {
      EditorLogService.instance.log(
        'Failed to write project registrant: $e',
        source: 'codegen',
        category: 'generate-one',
        level: DebuggerLogLevel.error,
      );
      return null;
    }
  }

  Future<void> _refreshComponents() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    final steps = StreamController<EditorSnackBarStep>();
    EditorMessenger.of(context).showSnackBar(
      EditorSnackBarEntry(
        title: 'Refreshing Components',
        message: 'Running just_code_gen scan...',
        type: EditorSnackBarType.info,
        progressStream: steps.stream,
      ),
    );

    final result = await ComponentIndexingService.instance.refreshNow();
    if (!mounted) {
      await steps.close();
      return;
    }

    setState(() => _isRefreshing = false);

    if (result.success) {
      // Re-register components from the freshly generated descriptors, then
      // rebuild the picker list.
      widget.sceneState.reloadCustomComponents();
      steps.add(
        const EditorSnackBarStep(
          message: 'Custom components refreshed successfully.',
        ),
      );
    } else {
      widget.sceneState.refresh();
      steps.add(
        EditorSnackBarStep(
          message: 'Component refresh failed: ${result.output}',
          isError: true,
        ),
      );
    }
    await steps.close();
  }

  @override
  Widget build(BuildContext context) {
    if (!_didScheduleInitialRefresh) {
      _didScheduleInitialRefresh = true;
      // Kick off one background refresh so annotation-discovered components
      // appear even before the user manually opens the refresh action.
      ComponentIndexingService.instance.scheduleRefresh();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Add + Refresh row ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: InkWell(
                  onTap: _toggle,
                  borderRadius: BorderRadius.circular(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _expanded
                          ? EditorTheme.selectionBg
                          : EditorTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _expanded
                            ? EditorTheme.primaryActive
                            : EditorTheme.border,
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _expanded ? Icons.remove_rounded : Icons.add_rounded,
                          size: 16,
                          color: EditorTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Add Component',
                            style: TextStyle(
                              color: EditorTheme.primaryBright,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: EditorTheme.primaryMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: kIsWeb
                    ? 'Refresh is only available on desktop builds.'
                    : 'Run just_code_gen scan and refresh component list',
                child: InkWell(
                  onTap: _isRefreshing || kIsWeb ? null : _refreshComponents,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: EditorTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: EditorTheme.border),
                    ),
                    alignment: Alignment.center,
                    child: _isRefreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: EditorTheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: kIsWeb
                                ? EditorTheme.primaryMuted
                                : EditorTheme.primary,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Expandable list ───────────────────────────────────────────────
        SizeTransition(
          sizeFactor: _heightFactor,
          axisAlignment: -1,
          child: _PickerList(
            searchCtrl: _searchCtrl,
            filtered: _filtered,
            existingTypes: _existingTypes,
            onAdd: _addComponent,
          ),
        ),
      ],
    );
  }
}

// ── Picker list (search field + grouped results) ──────────────────────────────

class _PickerList extends StatelessWidget {
  const _PickerList({
    required this.searchCtrl,
    required this.filtered,
    required this.existingTypes,
    required this.onAdd,
  });

  final TextEditingController searchCtrl;
  final List<ComponentEntry> filtered;
  final Set<String> existingTypes;
  final void Function(ComponentEntry) onAdd;

  @override
  Widget build(BuildContext context) {
    // Group filtered entries
    final Map<String, List<ComponentEntry>> grouped = {};
    for (final entry in filtered) {
      grouped.putIfAbsent(entry.group, () => []).add(entry);
    }
    // Sort groups in canonical order
    final orderedGroups = kComponentGroups
        .where((g) => grouped.containsKey(g))
        .toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDarkest,
        border: Border.all(color: EditorTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: <Widget>[
          // Search field
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchCtrl,
              autofocus: true,
              style: const TextStyle(
                color: EditorTheme.textPrimary,
                fontSize: 12,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search components…',
                hintStyle: const TextStyle(
                  color: EditorTheme.primaryMuted,
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: EditorTheme.primaryMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                filled: true,
                fillColor: EditorTheme.inputBg,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
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
                  borderSide: const BorderSide(
                    color: EditorTheme.primaryActive,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: EditorTheme.surfaceBg),
          // Results
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No components match your search.',
                      style: TextStyle(
                        color: EditorTheme.primaryMuted,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: _countItems(orderedGroups, grouped),
                    itemBuilder: (context, index) =>
                        _buildItem(index, orderedGroups, grouped),
                  ),
          ),
        ],
      ),
    );
  }

  // We render group headers + component rows in a flat list — compute the
  // total item count for the builder.
  int _countItems(
    List<String> groups,
    Map<String, List<ComponentEntry>> grouped,
  ) {
    return groups.fold(0, (sum, g) => sum + 1 + (grouped[g]?.length ?? 0));
  }

  Widget _buildItem(
    int index,
    List<String> groups,
    Map<String, List<ComponentEntry>> grouped,
  ) {
    int cursor = 0;
    for (final group in groups) {
      if (index == cursor) return _GroupHeader(label: group);
      cursor++;
      final entries = grouped[group]!;
      final localIndex = index - cursor;
      if (localIndex < entries.length) {
        final entry = entries[localIndex];
        final typeKey = entry.componentTypeName ?? entry.name;
        final alreadyAdded = existingTypes.contains(typeKey);
        return _ComponentRow(
          entry: entry,
          alreadyAdded: alreadyAdded,
          onTap: alreadyAdded ? null : () => onAdd(entry),
        );
      }
      cursor += entries.length;
    }
    return const SizedBox.shrink();
  }
}

// ── Group header ──────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: EditorTheme.primaryBright,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Component row ─────────────────────────────────────────────────────────────

class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.entry,
    required this.alreadyAdded,
    required this.onTap,
  });

  final ComponentEntry entry;
  final bool alreadyAdded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    style: TextStyle(
                      color: alreadyAdded
                          ? EditorTheme.hoverBgAlt
                          : EditorTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    entry.description,
                    style: TextStyle(
                      color: alreadyAdded
                          ? EditorTheme.hoverBg
                          : EditorTheme.primaryMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyAdded)
              const Text(
                'added',
                style: TextStyle(
                  color: EditorTheme.hoverBgAlt,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              const Icon(
                Icons.add_rounded,
                size: 14,
                color: EditorTheme.primaryMuted,
              ),
          ],
        ),
      ),
    );
  }
}
