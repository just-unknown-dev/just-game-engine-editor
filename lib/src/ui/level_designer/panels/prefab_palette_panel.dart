import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../level_designer_session.dart';
import '../../../core/prefabs/prefab_files.dart';
import '../../../core/scope/editor_scope_services.dart';

/// The palette of entity types the draw, paint and place tools make.
///
/// Grouped by category and colour-coded to match how each prefab draws in the
/// viewport, so the palette and the level read as the same vocabulary. A
/// search box narrows it; starred favourites come first; a prefab a module
/// draws a picture of (`EditorModule.prefabPictures`) shows that.
class PrefabPalettePanel extends StatefulWidget {
  const PrefabPalettePanel({super.key, required this.session});

  /// The designer session whose active prefab this sets.
  final LevelDesignerSession session;

  @override
  State<PrefabPalettePanel> createState() => _PrefabPalettePanelState();
}

class _PrefabPalettePanelState extends State<PrefabPalettePanel> {
  String _query = '';
  late ValueListenable<Set<String>> _favourites;

  LevelDesignerSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _favourites = PrefabFavourites.watch(session.scope.prefs);
  }

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => ValueListenableBuilder<int>(
      // The project's prefab files come and go with its files.
      valueListenable: session.scope.assetIndex.revision,
      builder: (context, _, _) {
        session.sessionPrefabs.registerAll(PrefabFiles.paletteEntries(session.scope));
        return ValueListenableBuilder<Set<String>>(
          valueListenable: _favourites,
          builder: (context, favourites, _) => _buildPalette(context, favourites),
        );
      },
    ),
  );

  bool _matches(PrefabDefinition prefab, String category) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      prefab.name,
      category,
      prefab.description ?? '',
      ...prefab.aliases,
    ].any((text) => text.toLowerCase().contains(q));
  }

  Widget _buildPalette(BuildContext context, Set<String> favourites) {
    // The scope's palette, then this session's samples, in the order the
    // categories were declared: a module's group lands where it asked to.
    final byCategory = <String, List<PrefabDefinition>>{};
    final mode = session.scope.sceneState.editingMode;
    final starred = <PrefabDefinition>[];
    for (final registry in [session.scope.prefabs, session.sessionPrefabs]) {
      for (final entry in registry.byCategory.entries) {
        final offered = [
          for (final p in entry.value)
            if (p.dimensions.allows(mode) && _matches(p, entry.key)) p,
        ];
        if (offered.isEmpty) continue;
        byCategory.putIfAbsent(entry.key, () => []).addAll(offered);
        starred.addAll(offered.where((p) => favourites.contains(p.id)));
      }
    }
    final categories = byCategory.keys.toList()
      ..sort(
        (a, b) => session.scope
            .prefabCategoryOrder(a)
            .compareTo(session.scope.prefabCategoryOrder(b)),
      );
    final sections = [
      if (starred.isNotEmpty) MapEntry('Favourites', starred),
      for (final c in categories) MapEntry(c, byCategory[c]!),
    ];
    // Pictures, where a module draws them, are bigger in space.
    final pictureSize = mode == jge.SceneMode.threeD ? 30.0 : 18.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: EditorSearchField(
            hint: 'Search prefabs',
            width: null,
            initial: _query,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: SignalBuilder<String?>(
            signal: session.controller.activePrefabId,
            builder: (context, activeId, _) => sections.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Nothing matches "${_query.trim()}"',
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  )
                : EditorScrollbar(
                    builder: (_, scroll) => ListView(
                      controller: scroll,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final entry in sections) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                            child: Text(
                              entry.key.toUpperCase(),
                              style: TextStyle(
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
                              picture: session.scope.prefabPictureOf(
                                prefab,
                                pictureSize,
                              ),
                              isActive: prefab.id == activeId,
                              isFavourite: favourites.contains(prefab.id),
                              onStar: () => PrefabFavourites.toggle(
                                session.scope.prefs,
                                prefab.id,
                              ),
                              onTap: () => _choose(prefab, mode),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _choose(PrefabDefinition prefab, jge.SceneMode mode) {
    session.controller.activePrefabId.value = prefab.id;
    // Selecting a prefab means you intend to place it, so switch away from
    // Select — otherwise the first click after picking one silently does
    // nothing. In 2-D it is drawn, in 3-D placed on what is clicked.
    if (session.controller.toolId.value == BuiltInTools.select) {
      session.setTool(
        mode == jge.SceneMode.twoD ? BuiltInTools.draw : BuiltInTools.place,
      );
    }
  }
}

class _PrefabTile extends StatefulWidget {
  const _PrefabTile({
    required this.prefab,
    required this.picture,
    required this.isActive,
    required this.isFavourite,
    required this.onStar,
    required this.onTap,
  });

  final PrefabDefinition prefab;

  /// What a module draws of it; its icon when null.
  final Widget? picture;
  final bool isActive;
  final bool isFavourite;
  final VoidCallback onStar;
  final VoidCallback onTap;

  @override
  State<_PrefabTile> createState() => _PrefabTileState();
}

class _PrefabTileState extends State<_PrefabTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final prefab = widget.prefab;
    final isActive = widget.isActive;
    return Tooltip(
      message: prefab.description ?? prefab.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: isActive ? EditorTheme.selectionBg : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  widget.picture ??
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
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_hovered || widget.isFavourite)
                    Tooltip(
                      message: widget.isFavourite
                          ? 'No longer a favourite'
                          : 'A favourite: listed first',
                      child: InkResponse(
                        onTap: widget.onStar,
                        radius: 12,
                        child: Icon(
                          widget.isFavourite ? Icons.star : Icons.star_border,
                          size: 14,
                          color: widget.isFavourite
                              ? EditorTheme.warning
                              : EditorTheme.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
