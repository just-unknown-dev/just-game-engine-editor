import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/scope/editor_scope_services.dart';
import '../tools/material_paint_3d_tool.dart';

/// The 3-D designer's MATERIALS section: the project's material files
/// (`*.material.json`), each pictured as the module that knows them draws
/// it. Click one to take it in hand and paint with it; double-click to open
/// it. Made from a folder's menu in Assets (New material).
class Materials3DPanel extends StatelessWidget {
  const Materials3DPanel({super.key, required this.scope, required this.setTool});

  /// The editor whose materials it lists.
  final EditorScope scope;

  /// Switches the designer's tool: to Paint material, once one is taken.
  final void Function(String toolId) setTool;

  /// How material files end.
  static const String ending = '.material.json';

  @override
  Widget build(BuildContext context) {
    final index = scope.assetIndex;
    return ValueListenableBuilder<int>(
      valueListenable: index.revision,
      builder: (context, _, _) => SignalBuilder<String?>(
        signal: scope.designer3D.materialInHand,
        builder: (context, inHand, _) {
          final materials = [
            for (final e in index.entries)
              if (!e.isDirectory && e.path.toLowerCase().endsWith(ending)) e,
          ];
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (materials.isEmpty)
                  Text(
                    'No materials yet: in Assets, a folder\'s menu has New material.',
                    style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in materials)
                        _MaterialTile(
                          entry: entry,
                          picture: entry.kind.preview?.call(context, index, entry, 40),
                          inHand: entry.path == inHand,
                          onTap: () {
                            scope.designer3D.materialInHand.value = entry.path;
                            setTool(MaterialPaint3DTool.toolId);
                          },
                          onOpen: () => scope.openInWorkspace(entry.path),
                        ),
                    ],
                  ),
                if (inHand != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.format_paint_outlined, size: 13, color: EditorTheme.textMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'In hand: ${_name(inHand)}  (P paints, Alt+click picks up)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
                        ),
                      ),
                      EditorIconButton(
                        icon: Icons.close,
                        tooltip: 'Put it down',
                        size: 22,
                        iconSize: 13,
                        onTap: () => scope.designer3D.materialInHand.value = null,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _name(String path) {
    final file = path.substring(path.lastIndexOf('/') + 1);
    return file.toLowerCase().endsWith(ending) ? file.substring(0, file.length - ending.length) : file;
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.entry,
    required this.picture,
    required this.inHand,
    required this.onTap,
    required this.onOpen,
  });

  final AssetEntry entry;
  final Widget? picture;
  final bool inHand;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${entry.path}\nClick to paint with it; double-click to open it',
    child: GestureDetector(
      onTap: onTap,
      onDoubleTap: onOpen,
      child: Container(
        width: 56,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: inHand ? EditorTheme.selectionBg : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: inHand ? EditorTheme.primary : EditorTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 40,
              child: picture ?? Icon(Icons.texture, size: 22, color: EditorTheme.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              Materials3DPanel._name(entry.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}
