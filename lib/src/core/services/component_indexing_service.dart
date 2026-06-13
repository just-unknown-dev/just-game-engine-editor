import 'dart:async';

import 'package:flutter/foundation.dart';

import 'component_codegen_runner.dart';

/// Debounced background indexing service for custom component discovery.
///
/// This schedules scan refreshes and notifies listeners when index data was
/// updated successfully.
class ComponentIndexingService {
  ComponentIndexingService._();

  static final ComponentIndexingService instance = ComponentIndexingService._();

  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Timer? _debounceTimer;
  bool _refreshInFlight = false;

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _listeners.clear();
  }

  void scheduleRefresh({
    Duration debounce = const Duration(milliseconds: 600),
    ComponentCodegenLog? onLog,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      await refreshNow(onLog: onLog);
    });
  }

  Future<ComponentCodegenResult> refreshNow({
    ComponentCodegenLog? onLog,
  }) async {
    if (_refreshInFlight) {
      return const ComponentCodegenResult(
        success: false,
        output: 'Component index refresh already in progress.',
      );
    }

    _refreshInFlight = true;
    try {
      final result = await runComponentIndexScan(onLog: onLog);
      if (result.success) {
        for (final listener in _listeners.toList(growable: false)) {
          listener();
        }
      }
      return result;
    } finally {
      _refreshInFlight = false;
    }
  }
}
