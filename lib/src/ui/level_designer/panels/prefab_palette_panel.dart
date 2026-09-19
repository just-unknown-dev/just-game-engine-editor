import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../level_designer_session.dart';
import '../tools/tool_registry.dart';
import '../state/prefab_registry.dart';

/// The palette of entity types the draw and paint tools place.
///
/// Grouped by category and colour-coded to match how each prefab draws in the
/// viewport, so the palette and the level read as the same vocabulary.
class PrefabPalettePanel extends StatelessWidget {
  const PrefabPalettePanel({super.key, required this.session});

  /// The designer session whose active prefab this sets.
  final LevelDesignerSession session;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildPalette(context),
  );

  Widget _buildPalette(BuildContext context) {
    // The scope's palette, then this session's samples, in the order the
    // categories were declared: a module's group lands where it asked to.
    final byCategory = <String, List<PrefabDefinition>>{};
    for (final registry in [session.scope.prefabs, session.sessionPrefabs]) {
      for (final entry in registry.byCategory.entries) {
        byCategory.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    }
    final categories = byCategory.keys.toList()
      ..sort(
        (a, b) => session.scope
            .prefabCategoryOrder(a)
            .compareTo(session.scope.prefabCategoryOrder(b)),
      );

    return SignalBuilder<String?>(
      signal: session.controller.activePrefabId,
      builder: (context, activeId, _) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          for (final entry in [
            for (final c in categories) MapEntry(c, byCategory[c]!),
          ]) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            for (final prefab in entry.value)
              _PrefabTile(
                prefab: prefab,
                isActive: prefab.id == activeId,
                onTap: () {
                  session.controller.activePrefabId.value = prefab.id;
                  // Selecting a prefab means you intend to place it, so switch
                  // away from Select — otherwise the first click after picking
                  // one silently does nothing.
                  if (session.controller.toolId.value == BuiltInTools.select) {
                    session.setTool(BuiltInTools.draw);
                  }
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _PrefabTile extends StatelessWidget {
  const _PrefabTile({
    required this.prefab,
    required this.isActive,
    required this.onTap,
  });

  final PrefabDefinition prefab;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: prefab.description ?? prefab.name,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: isActive ? EditorTheme.selectionBg : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: prefab.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Icon(prefab.icon, size: 12, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prefab.name,
                    style: TextStyle(
                      color: isActive
                          ? EditorTheme.textBright
                          : EditorTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
