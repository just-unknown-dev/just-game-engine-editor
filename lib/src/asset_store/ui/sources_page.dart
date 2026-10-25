import 'package:flutter/material.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import '../store_controller.dart';
import '../store_settings.dart';

/// Where the store reads from, which Flutter SDK it resolves with, its
/// download cache, and restoring missing packages.
class SourcesPage extends StatefulWidget {
  const SourcesPage({super.key, required this.controller});

  final StoreController controller;

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  StoreController get c => widget.controller;
  EditorPrefs get prefs => c.scope.prefs;
  String _newSource = '';
  String? _addProblem;
  String? _restoreMessage;

  @override
  Widget build(BuildContext context) {
    final text = TextStyle(
      color: EditorTheme.textSecondary,
      fontSize: EditorMetrics.fontBody,
      height: 1.4,
    );
    final muted = text.copyWith(color: EditorTheme.textMuted);
    final custom = StoreSettings.custom(prefs);
    final sdk = SdkLocator.locate(
      c.project.root,
      configured: prefs.get(StoreSettings.sdkPath).trim().isEmpty
          ? null
          : prefs.get(StoreSettings.sdkPath).trim(),
    );
    final cache = c.store.downloader.cache;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const EditorSectionHeader('Catalogs', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        Text(
          'The store lists what these catalogs offer. Add a studio\'s own '
          'catalog by its address, or a folder holding an index.json.',
          style: muted,
        ),
        const SizedBox(height: 8),
        if (c.usesSettings) ...[
          _sourceRow(
            SourceConfig.official,
            enabled: prefs.get(StoreSettings.official),
            onToggle: (v) async {
              await prefs.set(StoreSettings.official, v);
              await c.load(refresh: true);
            },
          ),
          for (var i = 0; i < custom.length; i++)
            _sourceRow(
              custom[i],
              enabled: custom[i].enabled,
              onToggle: (v) async {
                final list = [...custom];
                list[i] = SourceConfig(
                  list[i].url,
                  name: list[i].name,
                  enabled: v,
                );
                await StoreSettings.setCustom(prefs, list);
                await c.load(refresh: true);
              },
              onRemove: () async {
                await StoreSettings.setCustom(prefs, [...custom]..removeAt(i));
                await c.load(refresh: true);
              },
            ),
        ] else
          for (final s in c.sourceConfigs) _sourceRow(s, enabled: s.enabled),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: editorFieldDecoration(
                  hint: 'https://…/index.json, or a folder',
                ),
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: EditorMetrics.fontBody,
                ),
                onChanged: (v) => _newSource = v.trim(),
                onSubmitted: (_) => _add(custom),
              ),
            ),
            const SizedBox(width: 6),
            EditorButton(
              label: 'Add',
              icon: Icons.add_rounded,
              onPressed: () => _add(custom),
            ),
          ],
        ),
        if (_addProblem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _addProblem!,
              style: text.copyWith(color: EditorTheme.error),
            ),
          ),
        const SizedBox(height: 20),
        const EditorSectionHeader('Flutter SDK', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        Text(
          sdk == null
              ? 'Not found: installing needs it to run pub get. Set its folder '
                    'here, or run flutter pub get once in this project.'
              : 'Installs run pub get with the SDK in ${sdk.root}.',
          style: muted,
        ),
        const SizedBox(height: 6),
        CommitTextField(
          value: prefs.get(StoreSettings.sdkPath),
          decoration: editorFieldDecoration(
            hint: 'Leave empty to use the project\'s',
          ),
          onCommit: (v) async {
            await prefs.set(StoreSettings.sdkPath, v.trim());
            setState(() {});
          },
        ),
        const SizedBox(height: 20),
        const EditorSectionHeader('Downloads', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        Text(
          cache == null
              ? 'Downloads are not kept.'
              : 'Downloaded versions are kept in ${cache.dir} '
                    '(${_bytes(cache.sizeInBytes)}), shared by every project, '
                    'so an item installs again without the internet.',
          style: muted,
        ),
        if (cache != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: EditorButton(
              label: 'Clear downloads',
              icon: Icons.cleaning_services_outlined,
              kind: EditorButtonKind.ghost,
              onPressed: () {
                cache.clear();
                setState(() {});
              },
            ),
          ),
        ],
        const SizedBox(height: 20),
        const EditorSectionHeader('This project', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        Text(
          'After cloning a project that keeps packages/ out of git, Restore '
          'downloads the installed items again, checked against their '
          'recorded fingerprints.',
          style: muted,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            EditorButton(
              label: 'Restore missing packages',
              icon: Icons.settings_backup_restore_rounded,
              onPressed: c.busy ? null : _restore,
            ),
            const SizedBox(width: 8),
            if (_restoreMessage != null)
              Expanded(child: Text(_restoreMessage!, style: muted)),
          ],
        ),
      ],
    );
  }

  Widget _sourceRow(
    SourceConfig config, {
    required bool enabled,
    ValueChanged<bool>? onToggle,
    VoidCallback? onRemove,
  }) {
    final status = c.catalog?.sources
        .where((s) => s.config.url == config.url)
        .firstOrNull;
    final detail = !enabled
        ? 'Off'
        : status == null
        ? '…'
        : !status.loaded
        ? 'Could not be read: ${status.error}'
        : status.offline
        ? '${status.items} items (offline copy)'
        : '${status.items} items';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Row(
        children: [
          if (onToggle != null) ...[
            EditorToggle(value: enabled, onChanged: onToggle, label: ''),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status?.name ?? config.name ?? config.url,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: EditorMetrics.fontBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${config.url}  ·  $detail',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: status != null && !status.loaded && enabled
                        ? EditorTheme.error
                        : EditorTheme.textMuted,
                    fontSize: EditorMetrics.fontLabel,
                  ),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            EditorIconButton(
              icon: Icons.close_rounded,
              tooltip: 'Remove this catalog',
              onTap: onRemove,
            ),
        ],
      ),
    );
  }

  Future<void> _add(List<SourceConfig> custom) async {
    final url = _newSource;
    String? problem;
    if (url.isEmpty) {
      problem = 'Type an address or a folder.';
    } else if (url.startsWith('http://') &&
        !RegExp(r'^http://(localhost|127\.0\.0\.1)').hasMatch(url)) {
      problem = 'Catalogs on the web must use https.';
    } else if (!url.startsWith('https://') && !url.startsWith('http://')) {
      final path = url.endsWith('.json') ? url : '$url/index.json';
      if (!File(path).existsSync()) problem = 'There is no index.json there.';
    }
    if (custom.any((s) => s.url == url) || url == SourceConfig.official.url) {
      problem = 'That catalog is already listed.';
    }
    setState(() => _addProblem = problem);
    if (problem != null) return;
    await StoreSettings.setCustom(prefs, [...custom, SourceConfig(url)]);
    await c.load(refresh: true);
  }

  Future<void> _restore() async {
    final result = await c.restore();
    if (!mounted) return;
    setState(
      () => _restoreMessage = result.problems.isNotEmpty
          ? result.problems.join('\n')
          : result.restored.isEmpty
          ? 'Nothing is missing.'
          : 'Restored ${result.restored.join(', ')}.',
    );
  }
}

String _bytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
  return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
}
