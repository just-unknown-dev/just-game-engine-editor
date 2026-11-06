part of 'assets_dock.dart';

/// The Assets dock's parts: the tree, the grid and their rows.
extension _AssetsDockBuild on _AssetsDockState {
  Widget _body(List<AssetEntry> shown, AssetEntry? selected) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 190, child: _tree()),
              VerticalDivider(width: 1, color: EditorTheme.border),
              Expanded(
                child: Column(
                  children: [
                    _toolbar(),
                    Expanded(
                      child: shown.isEmpty
                          ? EditorEmptyState(
                              icon: Icons.folder_off_outlined,
                              title: _query.isEmpty && _kinds.isEmpty
                                  ? 'This folder is empty'
                                  : 'Nothing matches',
                              hint: _query.isEmpty && _kinds.isEmpty
                                  ? 'Files saved or dropped here show up by '
                                        'themselves.'
                                  : null,
                            )
                          : _grid
                          ? _gridView(shown)
                          : _listView(shown),
                    ),
                  ],
                ),
              ),
              if (selected != null && !selected.isDirectory) ...[
                VerticalDivider(width: 1, color: EditorTheme.border),
                SizedBox(width: 230, child: _preview(selected)),
              ],
            ],
          ),
        ),
        if (_trashed case final trashed?)
          Container(
            height: 26,
            color: EditorTheme.surfaceDarker,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Moved ${trashed.originalPath.split('/').last} to '
                    '${AssetIndex.trashFolder}/',
                    style: TextStyle(
                      color: EditorTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
                TextButton(onPressed: _restore, child: const Text('Restore')),
              ],
            ),
          ),
      ],
    );
  }

  Widget _draggable(AssetEntry entry, Widget child) => entry.isDirectory
      ? child
      : Draggable<String>(
          // The project-relative path: what an inspector field, and the
          // viewport, take.
          data: entry.path,
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: EditorTheme.dialogBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EditorTheme.border),
              ),
              child: Text(
                entry.name,
                style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
              ),
            ),
          ),
          // Dropped where the pointer is, not where the label's corner
          // is: the viewport places it under the pointer.
          dragAnchorStrategy: pointerDragAnchorStrategy,
          childWhenDragging: Opacity(opacity: 0.4, child: child),
          child: child,
        );

  Widget _thumbnail(AssetEntry entry, double size) {
    // A kind that draws its own picture (a module's: a 3-D model's render).
    final preview = entry.kind.preview?.call(context, _index, entry, size);
    if (preview != null) return preview;
    final image = thumbnailOf(_index, entry);
    if (image == null) {
      return Icon(
        assetIcon(entry.kind),
        size: size * 0.5,
        color: assetColor(entry.kind),
      );
    }
    final modified = _index.entryAt(image)?.modified;
    return Image(
      // Read again when it changed, so a re-saved sheet is not the cached one.
      image: ResizeImage.resizeIfNeeded(
        (size * 2).round(),
        null,
        fileImage(_index.absolute(image), version: modified),
      ),
      key: ValueKey('$image@$modified'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (context, _, _) => Icon(
        Icons.broken_image_outlined,
        size: size * 0.5,
        color: EditorTheme.textMuted,
      ),
    );
  }

  Widget _gridView(List<AssetEntry> shown) => GridView.builder(
    padding: const EdgeInsets.all(8),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 92,
      mainAxisExtent: 92,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
    ),
    itemCount: shown.length,
    itemBuilder: (context, i) {
      final entry = shown[i];
      final selected = entry.path == _selected;
      return _interactive(
        entry,
        Tooltip(
          message: entry.path,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? EditorTheme.selectionBg : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected
                    ? EditorTheme.primaryMutedLight
                    : Colors.transparent,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                Expanded(child: Center(child: _thumbnail(entry, 56))),
                const SizedBox(height: 3),
                Text(
                  entry.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? EditorTheme.textPrimary
                        : EditorTheme.textSecondary,
                    fontSize: 10,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _listView(List<AssetEntry> shown) => ListView.builder(
    itemExtent: 22,
    itemCount: shown.length,
    itemBuilder: (context, i) {
      final entry = shown[i];
      final selected = entry.path == _selected;
      return _interactive(
        entry,
        Container(
          color: selected ? EditorTheme.selectionBg : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                assetIcon(entry.kind),
                size: 13,
                color: assetColor(entry.kind),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  // A search shows where each hit lives.
                  _query.isEmpty && _kinds.isEmpty
                      ? entry.name
                      : entry.path.substring(_dir.length + 1),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? EditorTheme.textPrimary
                        : EditorTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              if (!entry.isDirectory)
                Text(
                  entry.sizeLabel,
                  style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _preview(AssetEntry entry) {
    final actions = [
      for (final a in widget.scope.assetActions)
        if (a.appliesTo(entry.path, isDirectory: false)) a,
    ];
    final modified = entry.modified;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: EditorTheme.surfaceDarker,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: EditorTheme.border),
              ),
              child: Center(child: _thumbnail(entry, 150)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            [
              entry.kind.label,
              entry.sizeLabel,
              if (modified != null)
                '${modified.year}-${modified.month.toString().padLeft(2, '0')}-'
                    '${modified.day.toString().padLeft(2, '0')}',
            ].join(' · '),
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              EditorIconButton(
                icon: Icons.open_in_new_rounded,
                tooltip: 'Open',
                onTap: () => _open(entry),
              ),
              for (final a in actions)
                EditorIconButton(
                  icon: a.icon,
                  tooltip: a.label,
                  onTap: () => a.run(widget.scope, entry.path),
                ),
              EditorIconButton(
                icon: Icons.travel_explore_rounded,
                tooltip: 'Find references',
                onTap: () => _showReferences(entry),
              ),
              const Spacer(),
              if (!entry.isPackage)
                EditorIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete (to the trash)',
                  color: EditorTheme.error,
                  onTap: () => _delete(entry),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
