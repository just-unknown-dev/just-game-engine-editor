import 'package:flutter/material.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../store_controller.dart';
import 'install_flow.dart';
import 'store_window.dart';

/// Everything about one item, and what can be done with it.
class ItemDetails extends StatelessWidget {
  const ItemDetails({super.key, required this.controller, required this.id});

  final StoreController controller;
  final String id;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final entry = c.entry(id);
    final installed = c.installed(id);
    if (entry == null && installed == null) {
      return const EditorEmptyState(
        icon: Icons.help_outline_rounded,
        title: 'Not in any of your sources',
      );
    }
    final item = entry?.item;
    final latest = item?.latest;
    final update = installed == null ? null : c.updateFor(id);
    final text = TextStyle(
      color: EditorTheme.textSecondary,
      fontSize: EditorMetrics.fontBody,
      height: 1.4,
    );
    final muted = text.copyWith(color: EditorTheme.textMuted);

    return Container(
      color: EditorTheme.menuBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (entry != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: ItemPicture(
                        controller: c,
                        entry: entry,
                        iconSize: 48,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  item?.name ?? id,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: EditorMetrics.fontHeading,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item != null) item.author?.name ?? item.publisher,
                    kindLabel(item?.kind ?? installed!.kind),
                    if (entry != null) 'from ${entry.sourceId}',
                  ].join(' · '),
                  style: muted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (item != null) TrustBadge(trust: item.trust),
                    if (installed != null)
                      EditorBadge(
                        label: 'INSTALLED ${installed.version}',
                        accent: EditorTheme.success,
                      ),
                    if (update != null)
                      EditorBadge(
                        label: 'UPDATE ${update.version}',
                        accent: EditorTheme.accent,
                        showDot: true,
                      ),
                  ],
                ),
                if (item != null && item.summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(item.summary, style: text),
                ],
                if (item?.description != null) ...[
                  const SizedBox(height: 6),
                  Text(item!.description!, style: text),
                ],
                if (latest != null) ...[
                  const EditorSectionHeader(
                    'Version',
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                  ),
                  Text(
                    [
                      'Latest ${latest.version}',
                      if (latest.published != null)
                        'published ${_date(latest.published!)}',
                    ].join(', '),
                    style: text,
                  ),
                  if (latest.notes != null) Text(latest.notes!, style: muted),
                ],
                if (item?.license != null) ...[
                  const EditorSectionHeader(
                    'Licence',
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                  ),
                  SelectableText(item!.license!.spdx, style: text),
                  if (item.license!.attribution != null)
                    SelectableText(
                      'Credit: ${item.license!.attribution}',
                      style: muted,
                    ),
                ],
                if (latest != null &&
                    (latest.dependencies.isNotEmpty ||
                        latest.requires.isNotEmpty ||
                        latest.nativePlugins.isNotEmpty)) ...[
                  const EditorSectionHeader(
                    'Needs',
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                  ),
                  for (final d in latest.dependencies.entries)
                    Text(
                      '${c.entry(d.key)?.item.name ?? d.key} ${d.value}',
                      style: text,
                    ),
                  for (final r in latest.requires.entries)
                    Text('${r.key} ${r.value}', style: muted),
                  if (latest.nativePlugins.isNotEmpty)
                    Text(
                      'Native plugins: ${latest.nativePlugins.join(', ')}',
                      style: muted.copyWith(color: EditorTheme.warning),
                    ),
                ],
                if (installed?.origin == ItemOrigin.linked) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This project uses your own checkout of it, at '
                    '${installed!.path}. Update it there.',
                    style: muted,
                  ),
                ],
                if (item?.sourceRepo != null) ...[
                  const EditorSectionHeader(
                    'Source',
                    padding: EdgeInsets.fromLTRB(0, 14, 0, 4),
                  ),
                  SelectableText(item!.sourceRepo!, style: muted),
                ],
              ],
            ),
          ),
          const EditorDivider(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: _actions(context, c, item, installed, update),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(
    BuildContext context,
    StoreController c,
    StoreItem? item,
    LockedItem? installed,
    StoreItemVersion? update,
  ) {
    final name = item?.name ?? id;
    final busy = c.busy;
    if (installed == null) {
      final paid = item?.latest?.access == AccessLevel.entitled;
      return [
        EditorButton(
          label: paid ? 'Paid items are coming soon' : 'Install',
          icon: Icons.download_rounded,
          kind: EditorButtonKind.primary,
          onPressed: busy || paid || item?.latest == null
              ? null
              : () => runPlan(
                  context,
                  c,
                  c.planInstall(id),
                  verb: 'Install',
                  subject: name,
                ),
        ),
      ];
    }
    final linked = installed.origin == ItemOrigin.linked;
    return [
      if (installed.kind == ItemKind.content && installed.path != null)
        EditorButton(
          label: 'Show in Assets',
          icon: Icons.folder_open_rounded,
          kind: EditorButtonKind.ghost,
          onPressed: () => c.scope.openDock('assets'),
        ),
      if (!installed.system && !linked)
        EditorButton(
          label: 'Uninstall',
          icon: Icons.delete_outline_rounded,
          kind: EditorButtonKind.danger,
          onPressed: busy
              ? null
              : () => runPlan(
                  context,
                  c,
                  c.planUninstall(id),
                  verb: 'Uninstall',
                  subject: name,
                ),
        ),
      if (update != null && !linked)
        EditorButton(
          label: 'Update to ${update.version}',
          icon: Icons.system_update_alt_rounded,
          kind: EditorButtonKind.primary,
          onPressed: busy
              ? null
              : () => runPlan(
                  context,
                  c,
                  c.planUpdate(id),
                  verb: 'Update',
                  subject: name,
                ),
        ),
    ];
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
