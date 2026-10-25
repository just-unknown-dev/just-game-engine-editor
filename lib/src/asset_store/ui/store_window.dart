import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../store_controller.dart';
import 'install_flow.dart';
import 'item_details.dart';
import 'sources_page.dart';

/// The Asset Store's window: a sidebar of pages and categories, a grid of
/// item cards, and the selected item's details.
class StoreWindow extends StatefulWidget {
  const StoreWindow({
    super.key,
    required this.controller,
    this.workspace,
    this.focusItem,
  });

  final StoreController controller;

  /// The workspace it is hosted in: close, full screen.
  final WorkspaceContext? workspace;

  /// An item to show first (from "Show in the Asset Store").
  final String? focusItem;

  @override
  State<StoreWindow> createState() => _StoreWindowState();
}

class _StoreWindowState extends State<StoreWindow> {
  StoreController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.focusItem != null) c.select(widget.focusItem);
    if (c.catalog == null) c.load();
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.workspace;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Container(
        color: EditorTheme.dialogBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspaceHeader(
              icon: Icons.storefront_rounded,
              title: 'Asset Store',
              showHistory: false,
              tools: [
                EditorSearchField(
                  hint: 'Search the store',
                  width: 260,
                  initial: c.query,
                  onChanged: c.search,
                ),
              ],
              trailing: [
                EditorIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Check the catalogs again',
                  onTap: c.loading ? null : () => c.load(refresh: true),
                ),
              ],
              fullScreen: ws?.fullScreen,
              onToggleFullScreen: ws?.onToggleFullScreen,
              onClose: ws?.onClose,
            ),
            ..._banners(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 196, child: _Sidebar(controller: c)),
                  const EditorDivider(vertical: true),
                  Expanded(child: _page()),
                  if (c.selected != null && c.tab != StoreTab.sources) ...[
                    const EditorDivider(vertical: true),
                    SizedBox(
                      width: 330,
                      child: ItemDetails(
                        key: ValueKey(c.selected),
                        controller: c,
                        id: c.selected!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (c.busy) _ProgressStrip(controller: c),
          ],
        ),
      ),
    );
  }

  List<Widget> _banners() => [
    if (c.restartPending)
      _Banner(
        icon: Icons.restart_alt_rounded,
        colour: EditorTheme.warning,
        text:
            'New editor code is installed. Hot restart (R in the terminal '
            'running the editor) or restart the editor to use it.',
      ),
    if (c.projectError != null)
      _Banner(
        icon: Icons.error_outline_rounded,
        colour: EditorTheme.error,
        text: 'The store cannot read this project: ${c.projectError}',
      ),
    // When no catalog could be read, the page itself says so.
    if (!c.unreachable)
      for (final s in c.troubledSources)
        _Banner(
          icon: s.loaded
              ? Icons.cloud_off_rounded
              : Icons.error_outline_rounded,
          colour: s.loaded ? EditorTheme.info : EditorTheme.warning,
          text: s.loaded
              ? 'Offline: showing the ${s.name} catalog as last downloaded.'
              : 'Could not read ${s.name}. ${s.problem}',
        ),
  ];

  Widget _page() {
    if (c.tab == StoreTab.sources) return SourcesPage(controller: c);
    if (c.catalog == null) {
      return c.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5))
          : EditorEmptyState(
              icon: Icons.storefront_outlined,
              title: 'The catalogs are not loaded',
              actionLabel: 'Try again',
              onAction: () => c.load(refresh: true),
            );
    }
    if (c.tab != StoreTab.installed && (c.unreachable || c.noSources)) {
      return _Unreachable(controller: c);
    }
    final items = c.shown;
    final kinds = c.kindCounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EditorToolbar(
          children: [
            for (final (kind, label) in const [
              (null, 'Everything'),
              (ItemKind.content, 'Art & sound'),
              (ItemKind.editorExtension, 'Editor tools'),
              (ItemKind.kit, 'Kits'),
              (ItemKind.runtimeLibrary, 'Libraries'),
            ])
              // A kind with nothing to show here is left out.
              if (kind == null || c.kind == kind || (kinds[kind] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: EditorChip(
                    label: label,
                    selected: c.kind == kind,
                    onTap: () => c.filterKind(kind),
                  ),
                ),
            const Spacer(),
            if (c.tab == StoreTab.browse)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: EditorChip(
                  label: 'Show experimental',
                  selected: c.showExperimental,
                  onTap: () => c.showExperimental = !c.showExperimental,
                ),
              ),
            SizedBox(
              width: 150,
              child: EditorDropdown<StoreSort>(
                value: c.sort,
                tooltip: 'Sort by',
                options: [
                  for (final s in StoreSort.values)
                    EditorDropdownOption(value: s, label: s.label),
                ],
                onChanged: c.sortBy,
              ),
            ),
            if (c.tab == StoreTab.updates && items.isNotEmpty) ...[
              const SizedBox(width: 6),
              EditorButton(
                label: 'Update all',
                icon: Icons.system_update_alt_rounded,
                kind: EditorButtonKind.primary,
                onPressed: c.busy
                    ? null
                    : () => runPlan(
                        context,
                        c,
                        c.planUpdateAll(),
                        verb: 'Update',
                        subject: 'every item',
                      ),
              ),
            ],
          ],
        ),
        Expanded(
          child: items.isEmpty
              ? EditorEmptyState(
                  icon: switch (c.tab) {
                    StoreTab.installed => Icons.inventory_2_outlined,
                    StoreTab.updates => Icons.check_circle_outline_rounded,
                    _ => Icons.search_off_rounded,
                  },
                  title: switch (c.tab) {
                    StoreTab.installed => 'Nothing from the store yet',
                    StoreTab.updates => 'Everything is up to date',
                    _ => 'Nothing matches',
                  },
                  hint: c.tab == StoreTab.browse && c.query.isNotEmpty
                      ? 'Try other words, or every category.'
                      : null,
                )
              : _grid(items),
        ),
      ],
    );
  }

  /// Cards with a 16:9 picture: each row's height follows the cards' width,
  /// so every picture keeps its shape at any window size.
  Widget _grid(List<CatalogEntry> items) => LayoutBuilder(
    builder: (context, box) {
      const pad = 12.0, gap = 10.0, widest = 250.0;
      final width = box.maxWidth - pad * 2;
      final columns = math.max(1, (width / (widest + gap)).ceil());
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return GridView.builder(
        padding: const EdgeInsets.all(pad),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: (cardWidth - 2) * 9 / 16 + ItemCard.infoHeight,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => ItemCard(controller: c, entry: items[i]),
      );
    },
  );
}

/// The page when no catalog can be read: why, what still works, and what
/// to try.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.controller});

  final StoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final installed = c.listedInstalled.length;
    final problems = {
      for (final s in c.catalog?.sources ?? const <SourceStatus>[]) ?s.problem,
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                c.noSources ? Icons.dns_outlined : Icons.cloud_off_rounded,
                size: 44,
                color: EditorTheme.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                c.noSources
                    ? 'No catalogs are turned on'
                    : "Can't reach the Asset Store",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: EditorMetrics.fontHeading,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (c.noSources)
                    'Turn one on, or add one, in Sources.'
                  else ...[
                    ...problems,
                    'Everything you have installed still works.',
                  ],
                ].join('\n'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: EditorMetrics.fontBody,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (!c.noSources)
                    EditorButton(
                      label: c.loading ? 'Trying…' : 'Try again',
                      icon: Icons.refresh_rounded,
                      kind: EditorButtonKind.primary,
                      onPressed: c.loading ? null : () => c.load(refresh: true),
                    ),
                  if (installed > 0)
                    EditorButton(
                      label: 'See what is installed ($installed)',
                      icon: Icons.inventory_2_outlined,
                      kind: EditorButtonKind.ghost,
                      onPressed: () => c.show(StoreTab.installed),
                    ),
                  EditorButton(
                    label: 'Sources',
                    icon: Icons.dns_outlined,
                    kind: c.noSources
                        ? EditorButtonKind.primary
                        : EditorButtonKind.ghost,
                    onPressed: () => c.show(StoreTab.sources),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller});

  final StoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final counts = c.categoryCounts;
    final categories = c.catalog?.catalog.categories ?? const [];
    Widget row(
      String label,
      IconData icon, {
      required bool selected,
      required VoidCallback onTap,
      int? count,
      Color? countColour,
      int depth = 0,
    }) => _SidebarRow(
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
      count: count,
      countColour: countColour,
      depth: depth,
    );
    final updates = c.catalog == null ? 0 : c.updates.length;
    return Container(
      color: EditorTheme.menuBg,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          row(
            'Browse',
            Icons.storefront_outlined,
            selected: c.tab == StoreTab.browse && c.category == null,
            onTap: () => c.show(StoreTab.browse),
          ),
          for (final cat in categories)
            if ((counts[cat.id] ?? 0) > 0)
              row(
                cat.label,
                Icons.label_outline_rounded,
                selected: c.tab == StoreTab.browse && c.category == cat.id,
                count: counts[cat.id],
                depth: 1,
                onTap: () => c.show(StoreTab.browse, category: cat.id),
              ),
          const SizedBox(height: 8),
          row(
            'Installed',
            Icons.inventory_2_outlined,
            selected: c.tab == StoreTab.installed,
            count: c.listedInstalled.length,
            onTap: () => c.show(StoreTab.installed),
          ),
          row(
            'Updates',
            Icons.system_update_alt_rounded,
            selected: c.tab == StoreTab.updates,
            count: updates,
            countColour: updates > 0 ? EditorTheme.accent : null,
            onTap: () => c.show(StoreTab.updates),
          ),
          row(
            'Sources',
            Icons.dns_outlined,
            selected: c.tab == StoreTab.sources,
            onTap: () => c.show(StoreTab.sources),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.count,
    this.countColour,
    this.depth = 0,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color? countColour;
  final int depth;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 28,
      padding: EdgeInsets.only(left: 12.0 + depth * 14, right: 10),
      decoration: BoxDecoration(
        color: selected ? EditorTheme.selectionBg : null,
        border: Border(
          left: BorderSide(
            color: selected ? EditorTheme.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: EditorMetrics.iconMd,
            color: selected ? EditorTheme.accent : EditorTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? EditorTheme.textPrimary
                    : EditorTheme.textSecondary,
                fontSize: EditorMetrics.fontBody,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: TextStyle(
                color: countColour ?? EditorTheme.textMuted,
                fontSize: EditorMetrics.fontLabel,
                fontWeight: countColour == null
                    ? FontWeight.w400
                    : FontWeight.w700,
              ),
            ),
        ],
      ),
    ),
  );
}

/// One item in the grid: its picture (with whether it is installed), name,
/// maker, a line about it, and where it comes from and how finished it is.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.controller, required this.entry});

  final StoreController controller;
  final CatalogEntry entry;

  /// The height of everything under the picture.
  static const double infoHeight = 112;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final item = entry.item;
    final selected = c.selected == item.id;
    final installed = c.installed(item.id);
    // A checkout of your own says Local, which is installed already.
    final linked = installed?.origin == ItemOrigin.linked;
    final update = installed == null || linked ? null : c.updateFor(item.id);
    final stage = item.stage;
    return Material(
      color: EditorTheme.surfaceBg,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
        hoverColor: EditorTheme.accent.withValues(alpha: 0.08),
        onTap: () => c.select(item.id),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
            border: Border.all(
              color: selected ? EditorTheme.accent : EditorTheme.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ItemPicture(controller: c, entry: entry),
                    if (update != null)
                      _StatePill(
                        icon: Icons.system_update_alt_rounded,
                        label: 'Update ${update.version}',
                        colour: EditorTheme.accent,
                      )
                    else if (installed != null && !linked)
                      _StatePill(
                        icon: Icons.check_rounded,
                        label: 'Installed',
                        colour: EditorTheme.success,
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: EditorMetrics.fontBody + 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          item.author?.name ?? item.publisher,
                          kindLabel(item.kind),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EditorTheme.textMuted,
                          fontSize: EditorMetrics.fontLabel,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: EditorTheme.textSecondary,
                          fontSize: EditorMetrics.fontLabel,
                          height: 1.35,
                        ),
                      ),
                      const Spacer(),
                      // One row: where it comes from, and its stage unless
                      // stable; on a narrow card it shrinks to fit.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SourceBadge(source: c.sourceOf(entry)),
                            if (stage != null && stage != ItemStage.stable) ...[
                              const SizedBox(width: 4),
                              StageBadge(stage: stage),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An item's picture, or its kind's icon while there is none.
class ItemPicture extends StatelessWidget {
  const ItemPicture({
    super.key,
    required this.controller,
    required this.entry,
    this.iconSize = 34,
  });

  final StoreController controller;
  final CatalogEntry entry;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    color: EditorTheme.surfaceDarker,
    child: FutureBuilder<File?>(
      future: controller.thumbnail(entry),
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) {
          return Center(
            child: Icon(
              kindIcon(entry.item.kind),
              size: iconSize,
              color: EditorTheme.textMuted.withValues(alpha: 0.6),
            ),
          );
        }
        return Image.file(
          file,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: iconSize,
              color: EditorTheme.textMuted,
            ),
          ),
        );
      },
    ),
  );
}

/// Whether a card's item is installed, on its picture's corner.
class _StatePill extends StatelessWidget {
  const _StatePill({
    required this.icon,
    required this.label,
    required this.colour,
  });

  final IconData icon;
  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDarker.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colour),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontSize: EditorMetrics.fontLabel,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The store's word for [kind].
String kindLabel(ItemKind kind) => switch (kind) {
  ItemKind.content => 'Art & sound',
  ItemKind.editorExtension => 'Editor tool',
  ItemKind.kit => 'Kit',
  ItemKind.runtimeLibrary => 'Library',
  ItemKind.template => 'Project template',
};

/// The icon that stands for [kind].
IconData kindIcon(ItemKind kind) => switch (kind) {
  ItemKind.content => Icons.image_outlined,
  ItemKind.editorExtension => Icons.handyman_outlined,
  ItemKind.kit => Icons.extension_outlined,
  ItemKind.runtimeLibrary => Icons.code_rounded,
  ItemKind.template => Icons.dashboard_customize_outlined,
};

/// Where an item comes from: Official, Third Party, Unlisted or Local.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final ItemSource source;

  @override
  Widget build(BuildContext context) => EditorBadge(
    label: source.label.toUpperCase(),
    accent: switch (source) {
      ItemSource.official => EditorTheme.primaryBright,
      ItemSource.thirdParty => EditorTheme.info,
      ItemSource.unlisted => EditorTheme.warning,
      ItemSource.local => EditorTheme.textMuted,
    },
  );
}

/// How finished an item (or the editor) is. Stable shows nothing.
class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage});

  final ItemStage stage;

  @override
  Widget build(BuildContext context) => switch (stage) {
    ItemStage.stable => const SizedBox.shrink(),
    ItemStage.beta => EditorBadge(label: 'BETA', accent: EditorTheme.info),
    ItemStage.experimental => EditorBadge(
      label: 'EXPERIMENTAL',
      accent: EditorTheme.warning,
    ),
    ItemStage.deprecated => EditorBadge(
      label: 'DEPRECATED',
      accent: EditorTheme.error,
    ),
  };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.colour, required this.text});

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    color: colour.withValues(alpha: 0.12),
    child: Row(
      children: [
        Icon(icon, size: EditorMetrics.iconMd, color: colour),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: EditorTheme.textSecondary,
              fontSize: EditorMetrics.fontBody,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.controller});

  final StoreController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.progress!;
    return Container(
      color: EditorTheme.surfaceDarker,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.message,
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: EditorMetrics.fontBody,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: p.fraction,
                    minHeight: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(EditorTheme.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          EditorButton(
            label: 'Cancel',
            kind: EditorButtonKind.ghost,
            onPressed: controller.cancel,
          ),
        ],
      ),
    );
  }
}
