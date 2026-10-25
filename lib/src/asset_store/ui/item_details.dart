import 'package:flutter/material.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../store_controller.dart';
import 'install_flow.dart';
import 'store_window.dart';

/// Everything about one item, and what can be done with it: its pictures,
/// what it is, the facts of the version picked, what it needs and does,
/// links, and the buttons.
class ItemDetails extends StatefulWidget {
  const ItemDetails({super.key, required this.controller, required this.id});

  final StoreController controller;
  final String id;

  @override
  State<ItemDetails> createState() => _ItemDetailsState();
}

class _ItemDetailsState extends State<ItemDetails> {
  /// The version picked in the version menu; null for the default.
  Version? _picked;

  /// The picture shown large.
  int _picture = 0;

  StoreController get c => widget.controller;
  String get id => widget.id;

  @override
  Widget build(BuildContext context) {
    final listed = c.entry(id);
    final installed = c.installed(id);
    if (listed == null && installed == null) {
      return const EditorEmptyState(
        icon: Icons.help_outline_rounded,
        title: 'Not in any of your sources',
      );
    }
    // An installed item no catalog lists is described by its own manifest.
    final entry = listed ?? c.localEntry(id)!;
    final item = entry.item;
    final linked = installed?.origin == ItemOrigin.linked;
    final versions = listed == null ? const <StoreItemVersion>[] : c.versionsOf(id);
    final have = installed == null ? null : Version.tryParse(installed.version);
    // The version described: the one picked, else the newest.
    final shown =
        (_picked == null ? null : item.versionOf(_picked!)) ?? item.latest;
    final update = installed == null || linked ? null : c.updateFor(id);

    return Container(
      color: EditorTheme.menuBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _gallery(entry),
                const SizedBox(height: 10),
                Text(
                  item.name,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: EditorMetrics.fontHeading,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    item.author?.name ?? item.publisher,
                    kindLabel(item.kind),
                  ].join(' · '),
                  style: _muted,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    SourceBadge(source: c.sourceOf(entry)),
                    if (item.stage case final stage?)
                      if (stage != ItemStage.stable) StageBadge(stage: stage),
                    if (installed != null && !linked)
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
                ..._stageNote(item),
                if (item.summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.summary,
                    style: _text.copyWith(color: EditorTheme.textPrimary),
                  ),
                ],
                if (item.description != null) ...[
                  const SizedBox(height: 6),
                  Text(item.description!, style: _text),
                ],
                _header('Details'),
                _fact(
                  'Version',
                  versions.length > 1 && !linked
                      ? _versionMenu(versions, shown, have)
                      : Text('${shown?.version ?? installed?.version ?? '–'}',
                          style: _text),
                ),
                if (installed != null)
                  _fact(
                    'Installed',
                    Text(
                      linked
                          ? 'Your own checkout, at ${installed.path}'
                          : installed.version,
                      style: _text,
                    ),
                  ),
                if (shown?.published case final published?)
                  _fact('Updated', Text(_date(published), style: _text)),
                if (shown?.archive case final archive?)
                  _fact('Size', Text(_size(archive.size), style: _text)),
                if (item.license case final license?)
                  _fact(
                    'Licence',
                    SelectableText(
                      [
                        license.spdx,
                        if (license.attribution != null)
                          'Credit: ${license.attribution}',
                      ].join('\n'),
                      style: _text,
                    ),
                  ),
                if (listed != null)
                  _fact(
                    'Catalog',
                    Text(c.sourceName(listed.sourceId), style: _text),
                  ),
                if (shown?.notes case final notes?) ...[
                  const SizedBox(height: 4),
                  Text(notes, style: _muted),
                ],
                if (shown != null &&
                    (shown.dependencies.isNotEmpty ||
                        shown.requires.isNotEmpty ||
                        shown.nativePlugins.isNotEmpty)) ...[
                  _header('Needs'),
                  for (final d in shown.dependencies.entries)
                    _Link(
                      label: '${c.entry(d.key)?.item.name ?? d.key} ${d.value}',
                      tooltip: 'Show it',
                      onTap: () => c.select(d.key),
                    ),
                  for (final r in shown.requires.entries)
                    Text('${_requirement(r.key)} ${r.value}', style: _muted),
                  if (shown.nativePlugins.isNotEmpty)
                    Text(
                      'Native plugins: ${shown.nativePlugins.join(', ')}',
                      style: _muted.copyWith(color: EditorTheme.warning),
                    ),
                ],
                if (shown != null && shown.permissions.isNotEmpty) ...[
                  _header('What it does'),
                  for (final p in ItemPermission.values)
                    if (shown.permissions.contains(p))
                      Text(
                        p.label,
                        style: _muted.copyWith(color: EditorTheme.warning),
                      ),
                  Text('As it declares.', style: _muted),
                ],
                ..._links(entry),
              ],
            ),
          ),
          ..._actionBar(context, item, installed, versions, have, shown, update),
        ],
      ),
    );
  }

  // ── Pictures ─────────────────────────────────────────────────────────────

  Widget _gallery(CatalogEntry entry) {
    final count = c.pictureCount(entry);
    final index = _picture.clamp(0, count == 0 ? 0 : count - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: count == 0
                ? ItemPicture(controller: c, entry: entry, iconSize: 48)
                : _Picture(future: c.picture(entry, index), kind: entry.item.kind),
          ),
        ),
        if (count > 1) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => InkWell(
                onTap: () => setState(() => _picture = i),
                borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
                child: Container(
                  width: 40 * 16 / 9,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
                    border: Border.all(
                      color: i == index ? EditorTheme.accent : EditorTheme.border,
                      width: i == index ? 1.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _Picture(
                    future: c.picture(entry, i),
                    kind: entry.item.kind,
                    iconSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Facts ────────────────────────────────────────────────────────────────

  TextStyle get _text => TextStyle(
    color: EditorTheme.textSecondary,
    fontSize: EditorMetrics.fontBody,
    height: 1.4,
  );

  TextStyle get _muted => _text.copyWith(color: EditorTheme.textMuted);

  Widget _header(String title) => EditorSectionHeader(
    title,
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
  );

  Widget _fact(String label, Widget value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(label, style: _muted),
          ),
        ),
        Expanded(child: value),
      ],
    ),
  );

  Widget _versionMenu(
    List<StoreItemVersion> versions,
    StoreItemVersion? shown,
    Version? have,
  ) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      width: 190,
      child: EditorDropdown<Version>(
        value: shown?.version,
        tooltip: 'Pick a version',
        options: [
          for (final v in versions)
            EditorDropdownOption(
              value: v.version,
              label: '${v.version}',
              detail: [
                if (v == versions.first) 'newest',
                if (v.version == have) 'installed',
                if (v.stage case final s? when s != ItemStage.stable)
                  s.label.toLowerCase(),
              ].join(', '),
            ),
        ],
        onChanged: (v) => setState(() => _picked = v),
      ),
    ),
  );

  List<Widget> _stageNote(StoreItem item) => switch (item.stage) {
    ItemStage.deprecated => [
      const SizedBox(height: 10),
      _StageNote(
        colour: EditorTheme.error,
        text:
            'Deprecated: it is no longer developed.'
            '${item.replacedBy == null ? '' : ' Use ${c.entry(item.replacedBy!)?.item.name ?? item.replacedBy} instead.'}',
      ),
    ],
    ItemStage.experimental => [
      const SizedBox(height: 10),
      _StageNote(
        colour: EditorTheme.warning,
        text: 'Experimental: it may change or break between versions.',
      ),
    ],
    _ => const [],
  };

  List<Widget> _links(CatalogEntry entry) {
    final source = Uri.tryParse(entry.item.sourceRepo ?? '');
    final links = [
      if (c.webPage(entry) case final page?)
        (Icons.storefront_outlined, 'Store page', page),
      if (source != null && source.scheme == 'https')
        (Icons.code_rounded, 'Source code', source),
      if (c.reportPage(entry) case final report?)
        (Icons.flag_outlined, 'Report a problem', report),
    ];
    if (links.isEmpty) return const [];
    return [
      _header('Links'),
      for (final (icon, label, uri) in links)
        _Link(
          icon: icon,
          label: label,
          tooltip: '$uri',
          onTap: () async {
            if (await c.openLink(uri) || !mounted) return;
            try {
              EditorMessenger.of(context).showSnackBar(
                EditorSnackBarEntry(
                  title: 'Could not open the browser',
                  message: 'The link is $uri',
                  type: EditorSnackBarType.warning,
                ),
              );
            } on Object {
              // Not under the editor's messenger (a test).
            }
          },
        ),
    ];
  }

  // ── Buttons ──────────────────────────────────────────────────────────────

  List<Widget> _actionBar(
    BuildContext context,
    StoreItem item,
    LockedItem? installed,
    List<StoreItemVersion> versions,
    Version? have,
    StoreItemVersion? shown,
    StoreItemVersion? update,
  ) {
    final actions = _actions(context, item, installed, have, shown, update);
    // A checkout of your own has nothing to press: no empty bar for it.
    if (actions.isEmpty) return const [];
    return [
      const EditorDivider(),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: actions,
        ),
      ),
    ];
  }

  List<Widget> _actions(
    BuildContext context,
    StoreItem item,
    LockedItem? installed,
    Version? have,
    StoreItemVersion? shown,
    StoreItemVersion? update,
  ) {
    final name = item.name;
    final busy = c.busy;
    if (installed == null) {
      final paid = shown?.access == AccessLevel.entitled;
      final picked = _picked != null && shown != null;
      return [
        EditorButton(
          label: paid
              ? 'Paid items are coming soon'
              : picked
              ? 'Install ${shown.version}'
              : 'Install',
          icon: Icons.download_rounded,
          kind: EditorButtonKind.primary,
          onPressed: busy || paid || shown == null || c.entry(id) == null
              ? null
              : () => runPlan(
                  context,
                  c,
                  c.planInstall(id, version: picked ? shown.version : null),
                  verb: 'Install',
                  subject: name,
                ),
        ),
      ];
    }
    final linked = installed.origin == ItemOrigin.linked;
    final switching =
        !linked && _picked != null && shown != null && shown.version != have;
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
      if (switching)
        EditorButton(
          label: 'Switch to ${shown.version}',
          icon: Icons.swap_vert_rounded,
          kind: EditorButtonKind.primary,
          onPressed: busy
              ? null
              : () => runPlan(
                  context,
                  c,
                  c.planInstall(id, version: shown.version),
                  verb: 'Switch',
                  subject: name,
                ),
        )
      else if (update != null)
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

  static String _requirement(String name) => switch (name) {
    'sdk' => 'Dart',
    'flutter' => 'Flutter',
    'just_game_engine' => 'Just Game Engine',
    'just_game_engine_editor' => 'Just Game Engine Editor',
    _ => name,
  };

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes bytes';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

/// A picture from [future], or [kind]'s icon while there is none.
class _Picture extends StatelessWidget {
  const _Picture({required this.future, required this.kind, this.iconSize = 48});

  final Future<File?> future;
  final ItemKind kind;
  final double iconSize;

  @override
  Widget build(BuildContext context) => Container(
    color: EditorTheme.surfaceDarker,
    child: FutureBuilder<File?>(
      future: future,
      builder: (context, snap) {
        final icon = Center(
          child: Icon(
            kindIcon(kind),
            size: iconSize,
            color: EditorTheme.textMuted.withValues(alpha: 0.6),
          ),
        );
        final file = snap.data;
        if (file == null) return icon;
        return Image.file(
          file,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => icon,
        );
      },
    ),
  );
}

/// A line that does something when pressed: show another item, open a
/// page.
class _Link extends StatelessWidget {
  const _Link({
    required this.label,
    required this.onTap,
    this.icon,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final link = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: EditorTheme.accent),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: EditorTheme.accent,
                  fontSize: EditorMetrics.fontBody,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: tooltip == null ? link : Tooltip(message: tooltip!, child: link),
    );
  }
}

/// A line about how finished an item is.
class _StageNote extends StatelessWidget {
  const _StageNote({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
      border: Border.all(color: colour.withValues(alpha: 0.45)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textPrimary,
        fontSize: EditorMetrics.fontBody,
        height: 1.4,
      ),
    ),
  );
}
