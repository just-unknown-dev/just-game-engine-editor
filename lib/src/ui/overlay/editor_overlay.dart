import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';

import '../panels/entity_inspector_panel.dart';
import '../panels/scene_picker_panel.dart';
import '../panels/scene_tree_panel.dart';
import '../theme/editor_theme.dart';
import '../../core/plugin/editor_plugin.dart';

// ── Public overlay host ───────────────────────────────────────────────────────

/// Wraps the game surface with the runtime editor UI.
///
/// When [plugin.isVisible] is false the widget is transparent and passes all
/// events through to the game. When visible it switches to a full-screen split
/// layout: game canvas on the left, editor panel on the right.
class JustGameEditorOverlay extends StatelessWidget {
  const JustGameEditorOverlay({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return gameChild;

    return FocusScope(
      node: plugin.gameFocusScopeNode,
      child: Focus(
        autofocus: true,
        canRequestFocus: true,
        child: AnimatedBuilder(
          animation: plugin,
          builder: (context, _) {
            if (!plugin.isVisible) {
              return AbsorbPointer(absorbing: false, child: gameChild);
            }

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _EditorSplitLayout(
                    plugin: plugin,
                    gameChild: gameChild,
                  ),
                ),
                const Positioned(
                  top: 16,
                  left: 16,
                  child: IgnorePointer(child: _EditorStatusBadge()),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditorSplitLayout extends StatelessWidget {
  const _EditorSplitLayout({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _EditorWorkspaceArea(plugin: plugin, gameChild: gameChild),
        ),
        SizedBox(width: 360, child: _EditorRightPanel(plugin: plugin)),
      ],
    );
  }
}

class _EditorWorkspaceArea extends StatefulWidget {
  const _EditorWorkspaceArea({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<_EditorWorkspaceArea> createState() => _EditorWorkspaceAreaState();
}

class _EditorWorkspaceAreaState extends State<_EditorWorkspaceArea> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            Positioned.fill(
              child: _GameCanvasArea(
                plugin: widget.plugin,
                gameChild: widget.gameChild,
              ),
            ),
            if (widget.plugin.isStatusPanelVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _CompactStatusDock(
                  plugin: widget.plugin,
                  maxDetailWidth: constraints.maxWidth,
                  maxDetailHeight: constraints.maxHeight,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GameCanvasArea extends StatelessWidget {
  const _GameCanvasArea({required this.plugin, required this.gameChild});

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        plugin.updateCanvasSize(size);

        return Listener(
          onPointerDown: plugin.onPointerDown,
          onPointerMove: plugin.onPointerMove,
          onPointerUp: plugin.onPointerUp,
          child: AbsorbPointer(absorbing: true, child: gameChild),
        );
      },
    );
  }
}

// ── Right panel ───────────────────────────────────────────────────────────────

enum _StatusMetricId { fps, update, entities, systems, memory, health, logs }

extension on _StatusMetricId {
  _StatusDetailSection get section => switch (this) {
    _StatusMetricId.fps => _StatusDetailSection.performance,
    _StatusMetricId.update => _StatusDetailSection.performance,
    _StatusMetricId.entities => _StatusDetailSection.ecs,
    _StatusMetricId.systems => _StatusDetailSection.ecs,
    _StatusMetricId.memory => _StatusDetailSection.memory,
    _StatusMetricId.health => _StatusDetailSection.health,
    _StatusMetricId.logs => _StatusDetailSection.logs,
  };

  String get label => switch (this) {
    _StatusMetricId.fps => 'FPS',
    _StatusMetricId.update => 'Update',
    _StatusMetricId.entities => 'Entities',
    _StatusMetricId.systems => 'Systems',
    _StatusMetricId.memory => 'Memory',
    _StatusMetricId.health => 'Health',
    _StatusMetricId.logs => 'Logs',
  };

  IconData get icon => switch (this) {
    _StatusMetricId.fps => Icons.speed_rounded,
    _StatusMetricId.update => Icons.timer_outlined,
    _StatusMetricId.entities => Icons.blur_linear_rounded,
    _StatusMetricId.systems => Icons.settings_input_component_rounded,
    _StatusMetricId.memory => Icons.memory_rounded,
    _StatusMetricId.health => Icons.favorite_rounded,
    _StatusMetricId.logs => Icons.article_outlined,
  };
}

enum _StatusDetailSection { performance, ecs, memory, health, logs }

extension on _StatusDetailSection {
  String get title => switch (this) {
    _StatusDetailSection.performance => 'Performance Details',
    _StatusDetailSection.ecs => 'ECS Details',
    _StatusDetailSection.memory => 'Memory Details',
    _StatusDetailSection.health => 'Health Details',
    _StatusDetailSection.logs => 'Log Details',
  };

  IconData get icon => switch (this) {
    _StatusDetailSection.performance => Icons.bolt_rounded,
    _StatusDetailSection.ecs => Icons.hub_rounded,
    _StatusDetailSection.memory => Icons.memory_rounded,
    _StatusDetailSection.health => Icons.favorite_rounded,
    _StatusDetailSection.logs => Icons.subject_rounded,
  };
}

class _CompactStatusDock extends StatefulWidget {
  const _CompactStatusDock({
    required this.plugin,
    required this.maxDetailWidth,
    required this.maxDetailHeight,
  });

  final JustGameEditorPlugin plugin;
  final double maxDetailWidth;
  final double maxDetailHeight;

  static const double _panelHeight = 56;
  static const double _detailWidth = 360;

  @override
  State<_CompactStatusDock> createState() => _CompactStatusDockState();
}

class _CompactStatusDockState extends State<_CompactStatusDock> {
  _StatusMetricId? _selectedMetric;
  final GlobalKey _stackKey = GlobalKey();
  final Map<_StatusMetricId, GlobalKey> _anchorKeys =
      <_StatusMetricId, GlobalKey>{};

  GlobalKey _anchorKeyFor(_StatusMetricId metric) {
    return _anchorKeys.putIfAbsent(metric, GlobalKey.new);
  }

  void _selectMetric(_StatusMetricId metric) {
    setState(() {
      _selectedMetric = _selectedMetric == metric ? null : metric;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedMetric = null;
    });
  }

  double _detailWidth() {
    final availableWidth = widget.maxDetailWidth - 24;
    if (availableWidth <= 0) {
      return 0;
    }
    return math.min(_CompactStatusDock._detailWidth, availableWidth);
  }

  double _detailLeftFor(_StatusMetricId metric, double detailWidth) {
    final stackContext = _stackKey.currentContext;
    final anchorContext = _anchorKeyFor(metric).currentContext;
    if (stackContext == null || anchorContext == null) {
      return 12;
    }

    final stackBox = stackContext.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        anchorBox == null ||
        !stackBox.hasSize ||
        !anchorBox.hasSize) {
      return 12;
    }

    final anchorCenter = anchorBox.localToGlobal(
      anchorBox.size.center(Offset.zero),
      ancestor: stackBox,
    );
    final minLeft = 12.0;
    final maxLeft = math.max(minLeft, widget.maxDetailWidth - detailWidth - 12);
    return (anchorCenter.dx - detailWidth / 2).clamp(minLeft, maxLeft);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.plugin.debuggerController,
      builder: (context, _) {
        final controller = widget.plugin.debuggerController;
        final snapshot = controller.snapshot;
        final performance = controller.performance;
        final memory = controller.memory;
        final logs = controller.logs;
        final health = controller.health;

        final warningCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.warning)
            .length;
        final errorCount = logs
            .where((entry) => entry.level == DebuggerLogLevel.error)
            .length;

        return Material(
          color: Colors.transparent,
          child: Stack(
            key: _stackKey,
            clipBehavior: Clip.none,
            children: <Widget>[
              Container(
                height: _CompactStatusDock._panelHeight,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111111),
                  borderRadius: BorderRadius.circular(0),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: <Widget>[
                              _StatusMetricButton(
                                metric: _StatusMetricId.fps,
                                anchorKey: _anchorKeyFor(_StatusMetricId.fps),
                                value: '${performance.currentFps}',
                                accent: EditorTheme.primary,
                                isSelected:
                                    _selectedMetric == _StatusMetricId.fps,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.update,
                                anchorKey: _anchorKeyFor(
                                  _StatusMetricId.update,
                                ),
                                value:
                                    '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
                                accent: EditorTheme.primaryBright,
                                isSelected:
                                    _selectedMetric == _StatusMetricId.update,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.entities,
                                anchorKey: _anchorKeyFor(
                                  _StatusMetricId.entities,
                                ),
                                value: '${snapshot.entityCount}',
                                accent: const Color(0xFF7DE6B1),
                                isSelected:
                                    _selectedMetric == _StatusMetricId.entities,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.systems,
                                anchorKey: _anchorKeyFor(
                                  _StatusMetricId.systems,
                                ),
                                value: '${snapshot.systemCount}',
                                accent: const Color(0xFF7CD7FF),
                                isSelected:
                                    _selectedMetric == _StatusMetricId.systems,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.memory,
                                anchorKey: _anchorKeyFor(
                                  _StatusMetricId.memory,
                                ),
                                value: _formatBytes(memory.rssBytes),
                                accent: const Color(0xFFFFC86B),
                                isSelected:
                                    _selectedMetric == _StatusMetricId.memory,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.health,
                                anchorKey: _anchorKeyFor(
                                  _StatusMetricId.health,
                                ),
                                value: health.hasWarnings
                                    ? '${health.messages.length} alerts'
                                    : 'Healthy',
                                accent: health.hasWarnings
                                    ? EditorTheme.warning
                                    : const Color(0xFF6DE0A7),
                                isSelected:
                                    _selectedMetric == _StatusMetricId.health,
                                onTap: _selectMetric,
                              ),
                              _StatusSeparator(),
                              _StatusMetricButton(
                                metric: _StatusMetricId.logs,
                                anchorKey: _anchorKeyFor(_StatusMetricId.logs),
                                value: '${logs.length} total',
                                trailing: errorCount > 0
                                    ? '$errorCount err'
                                    : '$warningCount warn',
                                accent: const Color(0xFFD9A7FF),
                                isSelected:
                                    _selectedMetric == _StatusMetricId.logs,
                                onTap: _selectMetric,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_selectedMetric != null)
                Positioned(
                  left: _detailLeftFor(_selectedMetric!, _detailWidth()),
                  bottom: _CompactStatusDock._panelHeight + 12,
                  child: IgnorePointer(
                    ignoring: false,
                    child: SizedBox(
                      width: _detailWidth(),
                      child: _StatusDetailCard(
                        controller: controller,
                        section: _selectedMetric!.section,
                        onClose: _clearSelection,
                        maxHeight:
                            widget.maxDetailHeight -
                            _CompactStatusDock._panelHeight -
                            40,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusMetricButton extends StatelessWidget {
  const _StatusMetricButton({
    required this.metric,
    required this.anchorKey,
    required this.value,
    required this.accent,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final _StatusMetricId metric;
  final GlobalKey anchorKey;
  final String value;
  final String? trailing;
  final Color accent;
  final bool isSelected;
  final ValueChanged<_StatusMetricId> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: anchorKey,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(metric),
          borderRadius: BorderRadius.circular(6),
          child: Ink(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(metric.icon, size: 11, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        metric.label,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                      if (trailing != null) ...<Widget>[
                        const SizedBox(width: 5),
                        Text(
                          trailing!,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: EditorTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: EditorTheme.textPrimary,
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

class _StatusDetailCard extends StatelessWidget {
  const _StatusDetailCard({
    required this.controller,
    required this.section,
    required this.onClose,
    required this.maxHeight,
  });

  final JustDebuggerController controller;
  final _StatusDetailSection section;
  final VoidCallback onClose;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxHeight.clamp(180, 320)),
            decoration: BoxDecoration(
              color: const Color(0xF41B1B1B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: EditorTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          section.icon,
                          size: 12,
                          color: EditorTheme.primaryBright,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              section.title,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: EditorTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _detailSubtitle(section, controller),
                              style: const TextStyle(
                                fontSize: 9,
                                color: EditorTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                        color: EditorTheme.textSecondary,
                        iconSize: 16,
                        splashRadius: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: _buildDetailContent(controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _detailSubtitle(
    _StatusDetailSection section,
    JustDebuggerController controller,
  ) {
    final logs = controller.logs;
    return switch (section) {
      _StatusDetailSection.performance =>
        'Frame ${controller.performance.frameNumber} • ${controller.performance.currentFps} FPS',
      _StatusDetailSection.ecs =>
        '${controller.snapshot.entityCount} entities • ${controller.snapshot.systemCount} systems',
      _StatusDetailSection.memory =>
        '${_formatBytes(controller.memory.rssBytes)} RSS • ${controller.memory.counters.length} counters',
      _StatusDetailSection.health =>
        controller.health.hasWarnings
            ? '${controller.health.messages.length} runtime warnings need attention'
            : 'No active runtime warnings',
      _StatusDetailSection.logs =>
        '${logs.length} captured events • latest ${logs.isEmpty ? '--' : logs.last.timeLabel}',
    };
  }

  Widget _buildDetailContent(JustDebuggerController controller) {
    return switch (section) {
      _StatusDetailSection.performance => _PerformanceDetailContent(
        controller: controller,
      ),
      _StatusDetailSection.ecs => _EcsDetailContent(controller: controller),
      _StatusDetailSection.memory => _MemoryDetailContent(
        controller: controller,
      ),
      _StatusDetailSection.health => _HealthDetailContent(
        controller: controller,
      ),
      _StatusDetailSection.logs => _LogsDetailContent(controller: controller),
    };
  }
}

class _StatusSeparator extends StatelessWidget {
  const _StatusSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _DetailStatTile extends StatelessWidget {
  const _DetailStatTile({required this.label, required this.value, this.hint});

  final String label;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EditorTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: EditorTheme.textMuted),
          ),
          if (hint != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.primaryMutedLight,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailSectionCard extends StatelessWidget {
  const _DetailSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: EditorTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PerformanceDetailContent extends StatelessWidget {
  const _PerformanceDetailContent({required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    final performance = controller.performance;
    final timings = performance.systemTimesMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _DetailStatTile(label: 'FPS', value: '${performance.currentFps}'),
            _DetailStatTile(
              label: 'Update Time',
              value: '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
            ),
            _DetailStatTile(
              label: 'Budget Left',
              value: '${performance.budgetRemainingMs.toStringAsFixed(1)} ms',
              hint: performance.isOverBudget
                  ? 'Over budget'
                  : 'Within frame budget',
            ),
            _DetailStatTile(
              label: 'Frame',
              value: '${performance.frameNumber}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailSectionCard(
          title: 'Hottest Systems',
          child: Column(
            children: timings
                .take(5)
                .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value.toStringAsFixed(2)} ms',
                          style: const TextStyle(
                            color: EditorTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _EcsDetailContent extends StatelessWidget {
  const _EcsDetailContent({required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final components = snapshot.componentUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _DetailStatTile(
              label: 'Entities',
              value: '${snapshot.entityCount}',
            ),
            _DetailStatTile(
              label: 'Active Entities',
              value: '${snapshot.activeEntityCount}',
            ),
            _DetailStatTile(label: 'Systems', value: '${snapshot.systemCount}'),
            _DetailStatTile(
              label: 'Archetypes',
              value: '${snapshot.archetypeCount}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailSectionCard(
          title: 'Top Components',
          child: Column(
            children: components
                .take(6)
                .map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '${entry.value}',
                          style: const TextStyle(
                            color: EditorTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _MemoryDetailContent extends StatelessWidget {
  const _MemoryDetailContent({required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    final memory = controller.memory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _DetailStatTile(
              label: 'App RSS',
              value: _formatBytes(memory.rssBytes),
            ),
            _DetailStatTile(label: 'Entities', value: '${memory.entityCount}'),
            _DetailStatTile(
              label: 'Components',
              value: '${memory.componentCount}',
            ),
            _DetailStatTile(
              label: 'Cache Fallback',
              value: memory.usingCacheFallback ? 'On' : 'Off',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailSectionCard(
          title: 'Memory Counters',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: memory.counters.entries
                .map((entry) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${entry.key}: ${entry.value}',
                      style: const TextStyle(color: EditorTheme.textSecondary),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _HealthDetailContent extends StatelessWidget {
  const _HealthDetailContent({required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    final health = controller.health;
    final performance = controller.performance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _DetailStatTile(
              label: 'Status',
              value: health.hasWarnings ? 'Attention' : 'Healthy',
            ),
            _DetailStatTile(
              label: 'Warnings',
              value: '${health.messages.length}',
            ),
            _DetailStatTile(label: 'FPS', value: '${performance.currentFps}'),
            _DetailStatTile(
              label: 'Budget State',
              value: performance.isOverBudget ? 'Exceeded' : 'OK',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailSectionCard(
          title: 'Current Signals',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: health.hasWarnings
                ? health.messages
                      .map((message) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: EditorTheme.warning,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  message,
                                  style: const TextStyle(
                                    color: EditorTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(growable: false)
                : const <Widget>[
                    Text(
                      'No active warnings. Runtime metrics look stable.',
                      style: TextStyle(color: EditorTheme.textSecondary),
                    ),
                  ],
          ),
        ),
      ],
    );
  }
}

class _LogsDetailContent extends StatelessWidget {
  const _LogsDetailContent({required this.controller});

  final JustDebuggerController controller;

  @override
  Widget build(BuildContext context) {
    final logs = controller.logs.reversed.take(5).toList(growable: false);
    final infoCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.info)
        .length;
    final warningCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.warning)
        .length;
    final errorCount = controller.logs
        .where((entry) => entry.level == DebuggerLogLevel.error)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _DetailStatTile(
              label: 'Total Logs',
              value: '${controller.logs.length}',
            ),
            _DetailStatTile(label: 'Info', value: '$infoCount'),
            _DetailStatTile(label: 'Warnings', value: '$warningCount'),
            _DetailStatTile(label: 'Errors', value: '$errorCount'),
          ],
        ),
        const SizedBox(height: 12),
        _DetailSectionCard(
          title: 'Recent Entries',
          child: Column(
            children: logs.isEmpty
                ? const <Widget>[
                    Text(
                      'No log entries captured yet.',
                      style: TextStyle(color: EditorTheme.textSecondary),
                    ),
                  ]
                : logs
                      .map((entry) {
                        final color = switch (entry.level) {
                          DebuggerLogLevel.info => const Color(0xFF7CD7FF),
                          DebuggerLogLevel.warning => EditorTheme.warning,
                          DebuggerLogLevel.error => EditorTheme.errorLight,
                        };
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '${entry.category.toUpperCase()} • ${entry.timeLabel}',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.message,
                                  style: const TextStyle(
                                    color: EditorTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }

  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

// ── Right panel ───────────────────────────────────────────────────────────────

class _EditorRightPanel extends StatelessWidget {
  const _EditorRightPanel({required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EditorTheme.panelBg,
      child: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: EditorTheme.border, width: 1),
            ),
          ),
          child: ListenableBuilder(
            listenable: plugin.sceneState,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _HeaderBar(plugin: plugin),
                  const Divider(height: 1, color: EditorTheme.border),
                  if (!plugin.sceneState.hasScene)
                    Expanded(
                      child: ScenePickerPanel(
                        onSceneSelected: (name) => plugin.openScene(name),
                      ),
                    )
                  else ...<Widget>[
                    // Scene tree (fixed height)
                    SizedBox(
                      height: 220,
                      child: SceneTreePanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onCreateEntity: plugin.createEntity,
                        onCreateGroup: plugin.createGroup,
                        onCreateGroupFrom: (entity) =>
                            plugin.createGroup(children: [entity]),
                        onDeleteEntity: plugin.deleteEntity,
                        onCopyEntity: plugin.copyEntity,
                        onPasteEntity: plugin.pasteEntity,
                        onReparentEntity: plugin.reparentEntity,
                      ),
                    ),
                    const Divider(height: 1, color: EditorTheme.border),
                    // Inspector (fills remaining space)
                    Expanded(
                      child: EntityInspectorPanel(
                        sceneState: plugin.sceneState,
                        world: plugin.engine.world,
                        onDetachFromParent: plugin.detachFromParent,
                        onGroupSelection: plugin.createGroup,
                      ),
                    ),
                    // Save button footer
                    _SaveFooter(plugin: plugin),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Header bar ────────────────────────────────────────────────────────────────

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          if (sceneName != null) ...<Widget>[
            Tooltip(
              message: 'Back to scene list',
              child: IconButton(
                onPressed: plugin.sceneState.closeScene,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                iconSize: 14,
                color: EditorTheme.primary,
                splashRadius: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            const SizedBox(width: 4),
          ] else ...<Widget>[
            const Icon(
              Icons.tune_rounded,
              color: EditorTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Just Runtime Editor',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: EditorTheme.textPrimary,
                  ),
                ),
                if (sceneName != null)
                  Text(
                    sceneName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: EditorTheme.primaryMuted,
                    ),
                  ),
              ],
            ),
          ),
          const _Badge(label: 'JIT'),
        ],
      ),
    );
  }
}

// ── Save footer ───────────────────────────────────────────────────────────────

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final isDirty = plugin.sceneState.isDirty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            if (isDirty)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: _Badge(label: 'UNSAVED', accent: EditorTheme.warning),
              ),
            const Spacer(),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: isDirty ? () => plugin.saveScene() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTheme.buttonBg,
                  disabledBackgroundColor: EditorTheme.surfaceBg,
                  foregroundColor: EditorTheme.primary,
                  disabledForegroundColor: EditorTheme.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 14),
                label: const Text(
                  'Save',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge (top-left corner) ────────────────────────────────────────────

class _EditorStatusBadge extends StatelessWidget {
  const _EditorStatusBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorTheme.statusBadgeBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EditorTheme.primary, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.visibility_rounded,
              size: 14,
              color: EditorTheme.textBright,
            ),
            const SizedBox(width: 6),
            const Text(
              'EDITOR: OPEN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: EditorTheme.textBright,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared badge chip ─────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.accent = EditorTheme.buttonBg});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: EditorTheme.textBadge,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
