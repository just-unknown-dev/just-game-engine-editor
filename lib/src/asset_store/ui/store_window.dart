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
    for (final s in c.troubledSources)
      _Banner(
        icon: s.loaded ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
        colour: s.loaded ? EditorTheme.info : EditorTheme.warning,
        text: s.loaded
            ? 'Offline: showing the ${s.name} catalog as last downloaded.'
            : 'Could not read ${s.name}: ${s.error}',
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
    final items = c.shown;
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
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: EditorChip(
                  label: label,
                  selected: c.kind == kind,
                  onTap: () => c.filterKind(kind),
                ),
              ),
            const Spacer(),
            if (c.tab == StoreTab.updates && items.isNotEmpty)
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
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 214,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) =>
                      ItemCard(controller: c, entry: items[i]),
                ),
        ),
      ],
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
            count: c.lock.items.length,
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

/// One item in the grid: its picture, name, maker and state.
class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.controller, required this.entry});

  final StoreController controller;
  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final item = entry.item;
    final selected = c.selected == item.id;
    final installed = c.installed(item.id);
    final update = installed == null ? null : c.updateFor(item.id);
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
              Expanded(
                child: ItemPicture(controller: c, entry: entry),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
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
                    const SizedBox(height: 2),
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
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (update != null)
                          EditorBadge(
                            label: 'UPDATE ${update.version}',
                            accent: EditorTheme.accent,
                            showDot: true,
                          )
                        else if (installed != null)
                          EditorBadge(
                            label: 'INSTALLED',
                            accent: EditorTheme.success,
                          ),
                        TrustBadge(trust: item.trust),
                        if (item.pricing.isFree)
                          EditorBadge(
                            label: 'FREE',
                            accent: EditorTheme.textMuted,
                          ),
                      ],
                    ),
                  ],
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
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
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

/// Who vouches for an item.
class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.trust});

  final TrustLevel trust;

  @override
  Widget build(BuildContext context) => switch (trust) {
    TrustLevel.official => EditorBadge(
      label: 'OFFICIAL',
      accent: EditorTheme.primaryBright,
    ),
    TrustLevel.verified => EditorBadge(
      label: 'VERIFIED',
      accent: EditorTheme.info,
    ),
    TrustLevel.community => EditorBadge(
      label: 'COMMUNITY',
      accent: EditorTheme.warning,
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
