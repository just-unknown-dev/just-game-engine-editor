part of 'editor_overlay.dart';

/// A draggable horizontal handle for resizing panels.
///
/// [onDrag] receives the vertical delta on each drag update — negative when
/// the user drags upward (expanding the panel below). Callers are responsible
/// for clamping the resulting size.
class _PanelResizeHandle extends StatelessWidget {
  const _PanelResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: Container(
          height: 12,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockLogsPanel extends StatelessWidget {
  const _DockLogsPanel({
    required this.controller,
    required this.height,
    required this.onResize,
    required this.onClose,
    required this.settings,
  });

  final JustDebuggerController controller;
  final double height;
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final TextEditingController _searchCtrl = TextEditingController();
    final Set<DebuggerLogLevel> _enabledLevels = <DebuggerLogLevel>{
      DebuggerLogLevel.info,
      DebuggerLogLevel.warning,
      DebuggerLogLevel.error,
    };
    // null means "all sources enabled" (before any source is explicitly excluded)
    Set<String>? _enabledSources;
    bool _collapseDuplicates = true;

    Set<String> _resolvedSources(Set<String> knownSources) {
      if (_enabledSources == null) {
        _enabledSources = Set<String>.from(knownSources);
      } else {
        // Auto-enable any source that appeared since last build.
        for (final src in knownSources) {
          _enabledSources!.add(src);
        }
      }
      return _enabledSources!;
    }

    List<_CollapsedLogEntry> _collapseEntries(List<EditorLogEntry> logs) {
      final collapsed = <_CollapsedLogEntry>[];
      for (final entry in logs) {
        if (collapsed.isEmpty) {
          collapsed.add(_CollapsedLogEntry(entry: entry, count: 1));
          if (collapsed.length >= settings.logLineClamp) {
            break;
          }
          continue;
        }

        final last = collapsed.last;
        final isDuplicate =
            last.entry.message == entry.message &&
            last.entry.source == entry.source &&
            last.entry.category == entry.category &&
            last.entry.level == entry.level;
        if (isDuplicate) {
          collapsed[collapsed.length - 1] = _CollapsedLogEntry(
            entry: last.entry,
            count: last.count + 1,
          );
        } else {
          collapsed.add(_CollapsedLogEntry(entry: entry, count: 1));
          if (collapsed.length >= settings.logLineClamp) {
            break;
          }
        }
      }
      return collapsed;
    }

    return ListenableBuilder(
      listenable: EditorLogService.instance,
      builder: (context, _) {
        final allLogs = EditorLogService.instance.entries;

        // Collect the ordered, distinct source list for filter chips.
        final knownSources = <String>{};
        for (final entry in allLogs) {
          knownSources.add(entry.source);
        }
        final enabledSources = _resolvedSources(knownSources);

        final orderedLogs = settings.logsAutoScroll
            ? allLogs.reversed.toList(growable: false)
            : allLogs.toList(growable: false);
        final query = _searchCtrl.text.trim().toLowerCase();
        final filtered = orderedLogs
            .where((entry) {
              if (!_enabledLevels.contains(entry.level)) {
                return false;
              }
              if (!enabledSources.contains(entry.source)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return entry.message.toLowerCase().contains(query) ||
                  entry.source.toLowerCase().contains(query) ||
                  entry.category.toLowerCase().contains(query) ||
                  (entry.details?.toLowerCase().contains(query) ?? false);
            })
            .toList(growable: false);
        final displayLogs = _collapseDuplicates
            ? _collapseEntries(filtered)
            : filtered
                  .take(settings.logLineClamp)
                  .map((entry) => _CollapsedLogEntry(entry: entry, count: 1))
                  .toList(growable: false);

        final infoCount = allLogs
            .where((entry) => entry.level == DebuggerLogLevel.info)
            .length;
        final warningCount = allLogs
            .where((entry) => entry.level == DebuggerLogLevel.warning)
            .length;
        final errorCount = allLogs
            .where((entry) => entry.level == DebuggerLogLevel.error)
            .length;
        return SizedBox(
          height: height,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xF41B1B1B),
                border: Border(
                  left: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
                  right: BorderSide(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
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
                  _PanelResizeHandle(onDrag: onResize),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFD9A7FF,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.article_outlined,
                            size: 11,
                            color: Color(0xFFD9A7FF),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Logs',
                          style: TextStyle(
                            fontSize: 11 * settings.effectiveTextScale,
                            fontWeight: FontWeight.w600,
                            color: EditorTheme.textPrimary,
                          ),
                        ),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: <Widget>[
                            _DetailStatTile(
                              label: 'Total Logs',
                              value: '${allLogs.length}',
                              settings: settings,
                            ),
                            _DetailStatTile(
                              label: 'Info',
                              value: '$infoCount',
                              settings: settings,
                            ),
                            _DetailStatTile(
                              label: 'Warnings',
                              value: '$warningCount',
                              settings: settings,
                            ),
                            _DetailStatTile(
                              label: 'Errors',
                              value: '$errorCount',
                              settings: settings,
                            ),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: onClose,
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
                  Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(10),
                      child: _LogsDetailContent(
                        controller: controller,
                        settings: settings,
                      ),
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
}

class _LogsDetailContent extends StatefulWidget {
  const _LogsDetailContent({required this.controller, required this.settings});

  final JustDebuggerController controller;
  final _OverlayUiSettings settings;

  @override
  State<_LogsDetailContent> createState() => _LogsDetailContentState();
}

class _LogsDetailContentState extends State<_LogsDetailContent> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<DebuggerLogLevel> _enabledLevels = <DebuggerLogLevel>{
    DebuggerLogLevel.info,
    DebuggerLogLevel.warning,
    DebuggerLogLevel.error,
  };
  // null means "all sources enabled" (before any source is explicitly excluded)
  Set<String>? _enabledSources;
  bool _collapseDuplicates = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Returns the enabled-sources set, initialising it from [knownSources] on
  /// first call so that every source starts enabled.
  Set<String> _resolvedSources(Set<String> knownSources) {
    if (_enabledSources == null) {
      _enabledSources = Set<String>.from(knownSources);
    } else {
      // Auto-enable any source that appeared since last build.
      for (final src in knownSources) {
        _enabledSources!.add(src);
      }
    }
    return _enabledSources!;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EditorLogService.instance,
      builder: (context, _) {
        final allLogs = EditorLogService.instance.entries;

        // Collect the ordered, distinct source list for filter chips.
        final knownSources = <String>{};
        for (final entry in allLogs) {
          knownSources.add(entry.source);
        }
        final enabledSources = _resolvedSources(knownSources);

        final orderedLogs = widget.settings.logsAutoScroll
            ? allLogs.reversed.toList(growable: false)
            : allLogs.toList(growable: false);
        final query = _searchCtrl.text.trim().toLowerCase();
        final filtered = orderedLogs
            .where((entry) {
              if (!_enabledLevels.contains(entry.level)) {
                return false;
              }
              if (!enabledSources.contains(entry.source)) {
                return false;
              }
              if (query.isEmpty) {
                return true;
              }
              return entry.message.toLowerCase().contains(query) ||
                  entry.source.toLowerCase().contains(query) ||
                  entry.category.toLowerCase().contains(query) ||
                  (entry.details?.toLowerCase().contains(query) ?? false);
            })
            .toList(growable: false);
        final displayLogs = _collapseDuplicates
            ? _collapseEntries(filtered)
            : filtered
                  .take(widget.settings.logLineClamp)
                  .map((entry) => _CollapsedLogEntry(entry: entry, count: 1))
                  .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _DetailSectionCard(
              sectionId: 'logs_controls',
              title: 'Controls',
              settings: widget.settings,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search logs',
                      hintStyle: const TextStyle(
                        color: EditorTheme.primaryMuted,
                        fontSize: 11,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: EditorTheme.primaryMuted,
                      ),
                      suffixIcon: SizedBox(
                        width: 500,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (knownSources.length > 1) ...<Widget>[
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: knownSources
                                    .toList(growable: false)
                                    .map(
                                      (src) =>
                                          _buildSourceChip(src, enabledSources),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                            IconButton(
                              onPressed: () async {
                                await EditorLogService.instance.clear();
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                              icon: const Icon(
                                Icons.delete_sweep_rounded,
                                size: 16,
                                color: EditorTheme.warning,
                              ),
                              tooltip: 'Clear logs',
                            ),
                          ],
                        ),
                      ),
                      filled: true,
                      fillColor: EditorTheme.inputBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: EditorTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: EditorTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: EditorTheme.primaryActive,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _buildLevelChip(DebuggerLogLevel.info, 'Info'),
                      _buildLevelChip(DebuggerLogLevel.warning, 'Warn'),
                      _buildLevelChip(DebuggerLogLevel.error, 'Error'),
                      FilterChip(
                        label: const Text('Collapse duplicates'),
                        selected: _collapseDuplicates,
                        onSelected: (value) {
                          setState(() {
                            _collapseDuplicates = value;
                          });
                        },
                        selectedColor: EditorTheme.selectionBg,
                        backgroundColor: EditorTheme.surfaceBg,
                        labelStyle: const TextStyle(
                          fontSize: 10,
                          color: EditorTheme.textSecondary,
                        ),
                        side: const BorderSide(color: EditorTheme.border),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),

                  if (EditorLogService.instance.persistencePath !=
                      null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      'Persisted to: ${EditorLogService.instance.persistencePath}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: EditorTheme.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DetailSectionCard(
              sectionId: 'logs_recent_entries',
              title: 'Recent Entries',
              settings: widget.settings,
              child: SingleChildScrollView(
                child: Column(
                  children: displayLogs.isEmpty
                      ? const <Widget>[
                          Text(
                            'No log entries matched the current filters.',
                            style: TextStyle(
                              fontSize: 10,
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ]
                      : displayLogs.map(_buildLogRow).toList(growable: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLevelChip(DebuggerLogLevel level, String label) {
    final enabled = _enabledLevels.contains(level);
    final color = switch (level) {
      DebuggerLogLevel.info => const Color(0xFF7CD7FF),
      DebuggerLogLevel.warning => EditorTheme.warning,
      DebuggerLogLevel.error => EditorTheme.errorLight,
    };
    return FilterChip(
      label: Text(label),
      selected: enabled,
      onSelected: (value) {
        setState(() {
          if (value) {
            _enabledLevels.add(level);
          } else {
            _enabledLevels.remove(level);
          }
        });
      },
      selectedColor: color.withValues(alpha: 0.14),
      backgroundColor: EditorTheme.surfaceBg,
      checkmarkColor: color,
      labelStyle: const TextStyle(
        fontSize: 10,
        color: EditorTheme.textSecondary,
      ),
      side: BorderSide(color: color.withValues(alpha: enabled ? 0.6 : 0.25)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSourceChip(String source, Set<String> enabledSources) {
    final enabled = enabledSources.contains(source);
    const accent = Color(0xFF9B8FFF);
    return FilterChip(
      label: Text(source),
      selected: enabled,
      onSelected: (value) {
        setState(() {
          _enabledSources ??= Set<String>.from(enabledSources);
          if (value) {
            _enabledSources!.add(source);
          } else {
            _enabledSources!.remove(source);
          }
        });
      },
      selectedColor: accent.withValues(alpha: 0.14),
      backgroundColor: EditorTheme.surfaceBg,
      checkmarkColor: accent,
      labelStyle: const TextStyle(
        fontSize: 10,
        color: EditorTheme.textSecondary,
      ),
      side: BorderSide(color: accent.withValues(alpha: enabled ? 0.6 : 0.25)),
      visualDensity: VisualDensity.compact,
    );
  }

  List<_CollapsedLogEntry> _collapseEntries(List<EditorLogEntry> logs) {
    final collapsed = <_CollapsedLogEntry>[];
    for (final entry in logs) {
      if (collapsed.isEmpty) {
        collapsed.add(_CollapsedLogEntry(entry: entry, count: 1));
        if (collapsed.length >= widget.settings.logLineClamp) {
          break;
        }
        continue;
      }

      final last = collapsed.last;
      final isDuplicate =
          last.entry.message == entry.message &&
          last.entry.source == entry.source &&
          last.entry.category == entry.category &&
          last.entry.level == entry.level;
      if (isDuplicate) {
        collapsed[collapsed.length - 1] = _CollapsedLogEntry(
          entry: last.entry,
          count: last.count + 1,
        );
      } else {
        collapsed.add(_CollapsedLogEntry(entry: entry, count: 1));
        if (collapsed.length >= widget.settings.logLineClamp) {
          break;
        }
      }
    }
    return collapsed;
  }

  Widget _buildLogRow(_CollapsedLogEntry collapsed) {
    final entry = collapsed.entry;
    final color = switch (entry.level) {
      DebuggerLogLevel.info => const Color(0xFF7CD7FF),
      DebuggerLogLevel.warning => EditorTheme.warning,
      DebuggerLogLevel.error => EditorTheme.errorLight,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                SelectableText(
                  '${entry.source.toUpperCase()} • ${entry.category} • ${entry.timeLabel}',
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (collapsed.count > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: SelectableText(
                      'x${collapsed.count}',
                      style: TextStyle(
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              entry.message,
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.textSecondary,
              ),
            ),
            if (entry.details != null &&
                entry.details!.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              SelectableText(
                entry.details!,
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 9,
                  color: EditorTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsedLogEntry {
  const _CollapsedLogEntry({required this.entry, required this.count});

  final EditorLogEntry entry;
  final int count;
}

class _DetailStatTile extends StatelessWidget {
  const _DetailStatTile({
    required this.label,
    required this.value,
    required this.settings,
  });

  final String label;
  final String value;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            spacing: 8,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11 * settings.effectiveTextScale,
                  color: EditorTheme.textMuted,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12 * settings.effectiveTextScale,
                  fontWeight: FontWeight.w700,
                  color: EditorTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
