part of 'editor_overlay.dart';

// ── Asset node ────────────────────────────────────────────────────────────────

class _AssetNode {
  _AssetNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.children,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final List<_AssetNode> children;
}

// ── Assets panel ──────────────────────────────────────────────────────────────

class _DockAssetsPanel extends StatefulWidget {
  const _DockAssetsPanel({
    required this.height,
    required this.onResize,
    required this.onClose,
    required this.settings,
  });

  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
  final _OverlayUiSettings settings;

  @override
  State<_DockAssetsPanel> createState() => _DockAssetsPanelState();
}

class _DockAssetsPanelState extends State<_DockAssetsPanel> {
  String? _selectedPath;
  final Set<String> _expandedFolders = {};
  final Map<String, List<_AssetNode>> _loadedChildren = {};
  _AssetNode? _assetRoot;
  _AssetNode? _scenesRoot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoots();
  }

  Future<void> _loadRoots() async {
    final base = Directory.current.path;
    final results = await Future.wait(<Future<_AssetNode>>[
      _buildNode('$base/assets'),
      _buildNode('$base/lib/game/scenes'),
    ]);
    if (!mounted) return;
    setState(() {
      _assetRoot = results[0];
      _scenesRoot = results[1];
      _isLoading = false;
    });
  }

  Future<_AssetNode> _buildNode(String dirPath) async {
    final name = dirPath.split('/').last.split(r'\').last;
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return _AssetNode(
        path: dirPath,
        name: name,
        isDirectory: true,
        children: <_AssetNode>[],
      );
    }

    final entities = await dir
        .list(recursive: false, followLinks: false)
        .toList();

    final dirs = <_AssetNode>[];
    final files = <_AssetNode>[];

    for (final entity in entities) {
      final entityName =
          entity.path.split('/').last.split(r'\').last;
      if (entity is Directory) {
        dirs.add(
          _AssetNode(
            path: entity.path,
            name: entityName,
            isDirectory: true,
            children: <_AssetNode>[],
          ),
        );
      } else if (entity is File) {
        files.add(
          _AssetNode(
            path: entity.path,
            name: entityName,
            isDirectory: false,
            children: <_AssetNode>[],
          ),
        );
      }
    }

    dirs.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    files.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return _AssetNode(
      path: dirPath,
      name: name,
      isDirectory: true,
      children: <_AssetNode>[...dirs, ...files],
    );
  }

  Future<void> _loadChildren(String dirPath) async {
    if (_loadedChildren.containsKey(dirPath)) return;
    final node = await _buildNode(dirPath);
    if (!mounted) return;
    setState(() {
      _loadedChildren[dirPath] = node.children;
    });
  }

  String _toRelativePath(String absolute) {
    final base = Directory.current.path.replaceAll(r'\', '/');
    final normalized = absolute.replaceAll(r'\', '/');
    if (normalized.startsWith('$base/')) {
      return normalized.substring(base.length + 1);
    }
    return normalized;
  }

  IconData _fileIcon(String name) {
    final ext =
        name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'webp' || 'gif' || 'svg' =>
        Icons.image_outlined,
      'mp3' || 'ogg' || 'wav' || 'aac' => Icons.audiotrack_rounded,
      'glsl' || 'frag' || 'vert' => Icons.lens_blur_rounded,
      'tmx' || 'tsx' => Icons.map_outlined,
      'json' || 'yaml' || 'yml' => Icons.data_object_rounded,
      'dart' => Icons.code_rounded,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  Widget _buildNodeRow(_AssetNode node, int depth) {
    final isExpanded = _expandedFolders.contains(node.path);
    final isSelected = _selectedPath == node.path;
    final children = _loadedChildren[node.path] ?? node.children;

    if (node.isDirectory) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildRowTile(
            icon: isExpanded
                ? Icons.folder_open_rounded
                : Icons.folder_rounded,
            iconColor: const Color(0xFFFFC86B),
            label: node.name,
            depth: depth,
            isSelected: isSelected,
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedFolders.remove(node.path);
                } else {
                  _expandedFolders.add(node.path);
                  _loadChildren(node.path);
                }
                _selectedPath = node.path;
              });
            },
            trailing: Icon(
              isExpanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              size: 12,
              color: EditorTheme.textMuted,
            ),
          ),
          if (isExpanded) ...<Widget>[
            ...children.map((child) => _buildNodeRow(child, depth + 1)),
            if (children.isEmpty)
              _buildEmptyRow(depth + 1),
          ],
        ],
      );
    }

    final tile = _buildRowTile(
      icon: _fileIcon(node.name),
      iconColor: EditorTheme.textMuted,
      label: node.name,
      depth: depth,
      isSelected: isSelected,
      onTap: () => setState(() => _selectedPath = node.path),
      trailing: null,
    );

    return Draggable<String>(
      data: _toRelativePath(node.path),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _fileIcon(node.name),
                size: 12,
                color: EditorTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                node.name,
                style: const TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: tile,
    );
  }

  Widget _buildRowTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int depth,
    required bool isSelected,
    required VoidCallback onTap,
    required Widget? trailing,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: isSelected
              ? EditorTheme.selectionBg
              : Colors.transparent,
          padding: EdgeInsets.only(
            left: 10.0 + depth * 14.0,
            right: 8,
            top: 3,
            bottom: 3,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11 * widget.settings.effectiveTextScale,
                    color: isSelected
                        ? EditorTheme.textPrimary
                        : EditorTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyRow(int depth) {
    return Padding(
      padding: EdgeInsets.only(left: 10.0 + depth * 14.0, top: 3, bottom: 3),
      child: const Text(
        'Empty folder',
        style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
      ),
    );
  }

  Widget _buildRootSection(String label, _AssetNode? root, bool exists) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        ),
      );
    }

    if (root == null || (!exists && root.children.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          '$label/ not found',
          style: const TextStyle(fontSize: 10, color: EditorTheme.textMuted),
        ),
      );
    }

    return _buildNodeRow(root, 0);
  }

  @override
  Widget build(BuildContext context) {
    final assetsExists = _assetRoot != null &&
        (_assetRoot!.children.isNotEmpty ||
            Directory('${Directory.current.path}/assets').existsSync());
    final scenesExists = _scenesRoot != null &&
        (_scenesRoot!.children.isNotEmpty ||
            Directory('${Directory.current.path}/lib/game/scenes')
                .existsSync());

    return SizedBox(
      height: widget.height,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xF41B1B1B),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: <Widget>[
              _PanelResizeHandle(onDrag: widget.onResize),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7DD8E0).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.folder_outlined,
                        size: 11,
                        color: Color(0xFF7DD8E0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Assets',
                      style: TextStyle(
                        fontSize: 11 * widget.settings.effectiveTextScale,
                        fontWeight: FontWeight.w600,
                        color: EditorTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                      color: EditorTheme.textSecondary,
                      iconSize: 14,
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildRootSectionHeader('assets/'),
                      _buildRootSection('assets', _assetRoot, assetsExists),
                      const SizedBox(height: 4),
                      _buildRootSectionHeader('lib/game/scenes/'),
                      _buildRootSection('scenes', _scenesRoot, scenesExists),
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

  Widget _buildRootSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: EditorTheme.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
