part of 'editor_overlay.dart';

enum _EditorSettingsTab {
  presets,
  appearance,
  runtime,
  logsWarnings,
  accessibility,
}

extension on _EditorSettingsTab {
  String get label => switch (this) {
    _EditorSettingsTab.presets => 'Presets',
    _EditorSettingsTab.appearance => 'Appearance',
    _EditorSettingsTab.runtime => 'Runtime',
    _EditorSettingsTab.logsWarnings => 'Logs & Warnings',
    _EditorSettingsTab.accessibility => 'Accessibility',
  };

  IconData get icon => switch (this) {
    _EditorSettingsTab.presets => Icons.auto_awesome_rounded,
    _EditorSettingsTab.appearance => Icons.palette_outlined,
    _EditorSettingsTab.runtime => Icons.tune_rounded,
    _EditorSettingsTab.logsWarnings => Icons.article_outlined,
    _EditorSettingsTab.accessibility => Icons.accessibility_new_rounded,
  };
}

class _EditorSettingsPanel extends StatefulWidget {
  const _EditorSettingsPanel({
    required this.initial,
    required this.onChanged,
    required this.onClose,
    required this.maxHeight,
  });

  final _OverlayUiSettings initial;
  final ValueChanged<_OverlayUiSettings> onChanged;
  final VoidCallback onClose;
  final double maxHeight;

  @override
  State<_EditorSettingsPanel> createState() => _EditorSettingsPanelState();
}

class _EditorSettingsPanelState extends State<_EditorSettingsPanel>
    with SingleTickerProviderStateMixin {
  static const String _lastTabPrefKey = 'editor.overlay.settings.activeTab';

  late _OverlayUiSettings _draft;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _tabController = TabController(
      length: _EditorSettingsTab.values.length,
      vsync: this,
    );
    _tabController.addListener(_handleTabChanged);
    _loadStoredTab();
  }

  @override
  void didUpdateWidget(covariant _EditorSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _draft = widget.initial;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStoredTab() async {
    final savedIndex = await _overlaySettingsStore.readIntByKey(
      _lastTabPrefKey,
      fallback: 0,
    );
    if (!mounted) {
      return;
    }

    _tabController.index = savedIndex.clamp(
      0,
      _EditorSettingsTab.values.length - 1,
    );
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      _overlaySettingsStore.writeIntByKey(
        _lastTabPrefKey,
        _tabController.index,
      );
    }
  }

  void _updateDraft(_OverlayUiSettings next) {
    setState(() {
      _draft = next;
    });
    widget.onChanged(next);
  }

  void _applyProfile(_OverlayProfilePreset preset) {
    final next = switch (preset) {
      _OverlayProfilePreset.compact => _draft.copyWith(
        textScale: 0.9,
        compactness: 0.85,
        cornerRadius: 2,
        metricRefreshMs: 250,
        logLineClamp: 8,
        logsAutoScroll: true,
        accessibilityMode: _AccessibilityMode.off,
      ),
      _OverlayProfilePreset.defaultProfile =>
        const _OverlayUiSettings.defaults(),
      _OverlayProfilePreset.readable => _draft.copyWith(
        textScale: 1.1,
        compactness: 1.0,
        cornerRadius: 8,
        metricRefreshMs: 150,
        logLineClamp: 12,
        logsAutoScroll: true,
        accessibilityMode: _AccessibilityMode.readable,
      ),
      _OverlayProfilePreset.streaming => _draft.copyWith(
        textScale: 1.0,
        compactness: 0.95,
        cornerRadius: 6,
        metricRefreshMs: 500,
        logLineClamp: 20,
        logsAutoScroll: true,
        accessibilityMode: _AccessibilityMode.highContrast,
      ),
    };
    _updateDraft(next);
  }

  Widget _tabView(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _draft.themeColor;
    final panelHeight = widget.maxHeight.clamp(260.0, 460.0).toDouble();

    return Material(
      color: Colors.transparent,
      child: Container(
        height: panelHeight,
        decoration: BoxDecoration(
          color: const Color(0xF41B1B1B),
          borderRadius: BorderRadius.circular(_draft.cornerRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune_rounded, size: 12, color: accent),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Editor Settings',
                          style: TextStyle(
                            fontSize: 12 * _draft.effectiveTextScale,
                            fontWeight: FontWeight.w500,
                            color: EditorTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Live preview enabled. Changes apply immediately.',
                          style: TextStyle(
                            fontSize: 9 * _draft.effectiveTextScale,
                            color: EditorTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _updateDraft(const _OverlayUiSettings.defaults()),
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: const Text('Reset'),
                  ),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: EditorTheme.textSecondary,
                    iconSize: 16,
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _EditorSettingsSummary(
                settings: _draft,
                activeTab: _EditorSettingsTab.values.elementAt(
                  _tabController.index,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: accent,
              labelColor: EditorTheme.textPrimary,
              labelStyle: TextStyle(
                fontSize: 10 * _draft.effectiveTextScale,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelColor: EditorTheme.textMuted,
              dividerColor: Colors.white.withValues(alpha: 0.06),
              tabs: _EditorSettingsTab.values
                  .map(
                    (tab) =>
                        Tab(icon: Icon(tab.icon, size: 16), text: tab.label),
                  )
                  .toList(growable: false),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: <Widget>[
                  _tabView(
                    _EditorSettingsPresetsTab(
                      settings: _draft,
                      onPresetSelected: _applyProfile,
                    ),
                  ),
                  _tabView(
                    _EditorSettingsAppearanceTab(
                      settings: _draft,
                      onChanged: _updateDraft,
                    ),
                  ),
                  _tabView(
                    _EditorSettingsRuntimeTab(
                      settings: _draft,
                      onChanged: _updateDraft,
                    ),
                  ),
                  _tabView(
                    _EditorSettingsLogsTab(
                      settings: _draft,
                      onChanged: _updateDraft,
                    ),
                  ),
                  _tabView(
                    _EditorSettingsAccessibilityTab(
                      settings: _draft,
                      onChanged: _updateDraft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSettingsSummary extends StatelessWidget {
  const _EditorSettingsSummary({
    required this.settings,
    required this.activeTab,
  });

  final _OverlayUiSettings settings;
  final _EditorSettingsTab activeTab;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          _SettingsInfoChip(label: 'Theme', value: settings.themePreset.label),
          _SettingsInfoChip(
            label: 'Metrics',
            value: '${settings.metricRefreshMs.round()} ms',
          ),
          _SettingsInfoChip(
            label: 'Logs',
            value: settings.logsAutoScroll ? 'Auto-scroll' : 'Static',
          ),
          _SettingsInfoChip(
            label: 'Accessibility',
            value: settings.accessibilityMode.label,
          ),
          _SettingsInfoChip(
            label: 'Grid',
            value: settings.showGrid
                ? '${settings.gridSize.toStringAsFixed(0)}u'
                : 'Hidden',
          ),
          _SettingsInfoChip(
            label: 'Snap',
            value: settings.gridSnappingEnabled ? 'Enabled' : 'Disabled',
          ),
          _SettingsInfoChip(label: 'View', value: activeTab.label),
        ],
      ),
    );
  }
}

class _EditorSettingsPresetsTab extends StatelessWidget {
  const _EditorSettingsPresetsTab({
    required this.settings,
    required this.onPresetSelected,
  });

  final _OverlayUiSettings settings;
  final ValueChanged<_OverlayProfilePreset> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'editor_settings_profiles',
          title: 'Profile Presets',
          settings: settings,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _OverlayProfilePreset.values
                .map(
                  (preset) => _SettingsChoiceChip(
                    label: preset.label,
                    color: settings.themeColor,
                    isSelected: false,
                    onTap: () => onPresetSelected(preset),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_profiles_notes',
          title: 'Preset Notes',
          settings: settings,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SettingsNoteLine(
                title: 'Compact',
                body: 'Tighter spacing and faster scanning for small screens.',
              ),
              _SettingsNoteLine(
                title: 'Default',
                body: 'Balanced values for general editing.',
              ),
              _SettingsNoteLine(
                title: 'Readable',
                body: 'Larger text and gentler spacing for extended sessions.',
              ),
              _SettingsNoteLine(
                title: 'Streaming',
                body: 'Higher contrast and longer log buffers for demos.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorSettingsAppearanceTab extends StatelessWidget {
  const _EditorSettingsAppearanceTab({
    required this.settings,
    required this.onChanged,
  });

  final _OverlayUiSettings settings;
  final ValueChanged<_OverlayUiSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'editor_settings_appearance_layout',
          title: 'Layout & Motion',
          settings: settings,
          child: Column(
            children: <Widget>[
              _SettingsSliderRow(
                label: 'Text Size',
                value: settings.textScale,
                min: 0.85,
                max: 1.35,
                onChanged: (value) =>
                    onChanged(settings.copyWith(textScale: value)),
              ),
              _SettingsSliderRow(
                label: 'Corner Radius',
                value: settings.cornerRadius,
                min: 0,
                max: 14,
                onChanged: (value) =>
                    onChanged(settings.copyWith(cornerRadius: value)),
              ),
              _SettingsSliderRow(
                label: 'Compactness',
                value: settings.compactness,
                min: 0.8,
                max: 1.2,
                onChanged: (value) =>
                    onChanged(settings.copyWith(compactness: value)),
              ),
              _SettingsSliderRow(
                label: 'Animation Speed',
                value: settings.animationSpeed,
                min: 0.6,
                max: 1.8,
                onChanged: (value) =>
                    onChanged(settings.copyWith(animationSpeed: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_appearance_theme',
          title: 'Theme Accent',
          settings: settings,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _SettingsThemePreset.values
                .map(
                  (preset) => _SettingsChoiceChip(
                    label: preset.label,
                    color: preset.color,
                    isSelected: settings.themePreset == preset,
                    onTap: () =>
                        onChanged(settings.copyWith(themePreset: preset)),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_appearance_badge',
          title: 'Status Badge',
          settings: settings,
          child: _SettingsSwitchRow(
            title: 'Show editor status badge',
            value: settings.showStatusBadge,
            onChanged: (value) =>
                onChanged(settings.copyWith(showStatusBadge: value)),
          ),
        ),
      ],
    );
  }
}

class _EditorSettingsRuntimeTab extends StatelessWidget {
  const _EditorSettingsRuntimeTab({
    required this.settings,
    required this.onChanged,
  });

  final _OverlayUiSettings settings;
  final ValueChanged<_OverlayUiSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'editor_settings_runtime_metrics',
          title: 'Metric Sampling',
          settings: settings,
          child: Column(
            children: <Widget>[
              _SettingsSliderRow(
                label: 'Metric Refresh',
                value: settings.metricRefreshMs,
                min: 33,
                max: 1000,
                suffix: 'ms',
                onChanged: (value) =>
                    onChanged(settings.copyWith(metricRefreshMs: value)),
              ),
              _SettingsEnumDropdown<_WarningSeverityMode>(
                label: 'Warning Severity',
                value: settings.warningSeverity,
                items: _WarningSeverityMode.values,
                itemLabel: (mode) => mode.label,
                onChanged: (value) =>
                    onChanged(settings.copyWith(warningSeverity: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_runtime_ecs',
          title: 'ECS Warning Rules',
          settings: settings,
          child: Column(
            children: <Widget>[
              _SettingsSwitchRow(
                title: 'Warn when no systems are registered',
                value: settings.ecsWarnOnNoSystems,
                onChanged: (value) =>
                    onChanged(settings.copyWith(ecsWarnOnNoSystems: value)),
              ),
              _SettingsSwitchRow(
                title: 'Warn on inactive entity ratio',
                value: settings.ecsWarnOnInactive,
                onChanged: (value) =>
                    onChanged(settings.copyWith(ecsWarnOnInactive: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_runtime_grid',
          title: 'Grid & Snapping',
          settings: settings,
          child: Column(
            children: <Widget>[
              _SettingsSwitchRow(
                title: 'Show infinite grid on canvas',
                value: settings.showGrid,
                onChanged: (value) =>
                    onChanged(settings.copyWith(showGrid: value)),
              ),
              _SettingsSwitchRow(
                title: 'Snap movement and scale to grid',
                value: settings.gridSnappingEnabled,
                onChanged: (value) =>
                    onChanged(settings.copyWith(gridSnappingEnabled: value)),
              ),
              _SettingsSliderRow(
                label: 'Grid Size',
                value: settings.gridSize,
                min: 4,
                max: 256,
                digits: 0,
                suffix: 'u',
                onChanged: (value) => onChanged(
                  settings.copyWith(gridSize: value.roundToDouble()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorSettingsLogsTab extends StatelessWidget {
  const _EditorSettingsLogsTab({
    required this.settings,
    required this.onChanged,
  });

  final _OverlayUiSettings settings;
  final ValueChanged<_OverlayUiSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'editor_settings_logs_display',
          title: 'Log Display',
          settings: settings,
          child: Column(
            children: <Widget>[
              _SettingsSliderRow(
                label: 'Visible Log Lines',
                value: settings.logLineClamp.toDouble(),
                min: 3,
                max: 40,
                digits: 0,
                onChanged: (value) =>
                    onChanged(settings.copyWith(logLineClamp: value.round())),
              ),
              _SettingsSwitchRow(
                title: 'Auto-scroll to newest entries',
                value: settings.logsAutoScroll,
                onChanged: (value) =>
                    onChanged(settings.copyWith(logsAutoScroll: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_logs_guidance',
          title: 'Behavior',
          settings: settings,
          child: Text(
            settings.logsAutoScroll
                ? 'Newest entries stay visible automatically. Increase the line clamp for debugging sessions.'
                : 'Log ordering stays fixed. Use a smaller line clamp when you want tighter dock spacing.',
            style: const TextStyle(
              fontSize: 10,
              color: EditorTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorSettingsAccessibilityTab extends StatelessWidget {
  const _EditorSettingsAccessibilityTab({
    required this.settings,
    required this.onChanged,
  });

  final _OverlayUiSettings settings;
  final ValueChanged<_OverlayUiSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _DetailSectionCard(
          sectionId: 'editor_settings_accessibility_mode',
          title: 'Accessibility Mode',
          settings: settings,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SettingsEnumDropdown<_AccessibilityMode>(
                label: 'Mode',
                value: settings.accessibilityMode,
                items: _AccessibilityMode.values,
                itemLabel: (mode) => mode.label,
                onChanged: (value) =>
                    onChanged(settings.copyWith(accessibilityMode: value)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _SettingsInfoChip(
                    label: 'Text Scale',
                    value: settings.effectiveTextScale.toStringAsFixed(2),
                  ),
                  _SettingsInfoChip(
                    label: 'Separator',
                    value: settings.accessibilityMode.separatorThickness
                        .toStringAsFixed(1),
                  ),
                  _SettingsInfoChip(
                    label: 'Alpha',
                    value: settings.accessibilityMode.separatorAlpha
                        .toStringAsFixed(2),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _DetailSectionCard(
          sectionId: 'editor_settings_accessibility_notes',
          title: 'Mode Notes',
          settings: settings,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _SettingsNoteLine(
                title: 'Off',
                body: 'Uses the base visual density and separator contrast.',
              ),
              _SettingsNoteLine(
                title: 'Readable',
                body: 'Adds moderate size and contrast adjustments.',
              ),
              _SettingsNoteLine(
                title: 'High Contrast',
                body: 'Pushes readability for presentations and long sessions.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsChoiceChip extends StatelessWidget {
  const _SettingsChoiceChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoChip extends StatelessWidget {
  const _SettingsInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 10,
          color: EditorTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SettingsNoteLine extends StatelessWidget {
  const _SettingsNoteLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$title: ',
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: body,
              style: const TextStyle(
                fontSize: 10,
                color: EditorTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsEnumDropdown<T> extends StatelessWidget {
  const _SettingsEnumDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dropdownColor: const Color(0xFF1A1A1A),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                itemLabel(item),
                style: TextStyle(fontSize: 10, color: EditorTheme.textPrimary),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (next) {
        if (next != null) {
          onChanged(next);
        }
      },
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.6,
            child: Switch.adaptive(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _SettingsSliderRow extends StatefulWidget {
  const _SettingsSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.digits = 2,
    this.suffix = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int digits;
  final String suffix;

  @override
  State<_SettingsSliderRow> createState() => _SettingsSliderRowState();
}

class _SettingsSliderRowState extends State<_SettingsSliderRow> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  double get _step => widget.digits == 0 ? 1.0 : 0.05;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SettingsSliderRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _formatValue(double value) => value.toStringAsFixed(widget.digits);

  double _clampAndRound(double value) {
    final clamped = value.clamp(widget.min, widget.max).toDouble();
    if (widget.digits <= 0) {
      return clamped.roundToDouble();
    }
    final scale = math.pow(10, widget.digits).toDouble();
    return (clamped * scale).round() / scale;
  }

  void _commitFromText() {
    final parsed = double.tryParse(_controller.text.trim());
    final next = _clampAndRound(parsed ?? widget.value);
    _controller.text = _formatValue(next);
    widget.onChanged(next);
  }

  void _nudge(double delta) {
    final next = _clampAndRound(widget.value + delta);
    _controller.text = _formatValue(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = widget.value.toStringAsFixed(widget.digits);
    final suffixText = widget.suffix.isEmpty ? '' : ' ${widget.suffix}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${widget.label} ($displayValue$suffixText)',
          style: const TextStyle(
            color: EditorTheme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: widget.value <= widget.min
                    ? null
                    : () => _nudge(-_step),
                icon: const Icon(Icons.remove_rounded, size: 16),
                color: EditorTheme.textSecondary,
                disabledColor: EditorTheme.border,
                splashRadius: 16,
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: EditorTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: _formatValue(widget.value),
                    suffixText: widget.suffix.isEmpty ? null : widget.suffix,
                    suffixStyle: const TextStyle(
                      fontSize: 10,
                      color: EditorTheme.textMuted,
                    ),
                  ),
                  onSubmitted: (_) => _commitFromText(),
                  onEditingComplete: _commitFromText,
                ),
              ),
              IconButton(
                onPressed: widget.value >= widget.max
                    ? null
                    : () => _nudge(_step),
                icon: const Icon(Icons.add_rounded, size: 16),
                color: EditorTheme.textSecondary,
                disabledColor: EditorTheme.border,
                splashRadius: 16,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
