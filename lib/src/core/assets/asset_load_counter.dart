/// Counts the loads that pass through it, so the scene loader can say how
/// many of those asked for have arrived.
///
/// Counted from the last [restart]: a load that was under way before it
/// counts neither as asked for nor as arrived.
class AssetLoadCounter {
  int _round = 0;
  int _started = 0;
  int _finished = 0;

  /// Loads asked for since the last [restart].
  int get started => _started;

  /// Of [started], those that have arrived — loaded, or failed to.
  int get finished => _finished;

  /// Of [started], those still loading.
  int get pending => _started - _finished;

  /// Counts afresh from now.
  void restart() {
    _round++;
    _started = 0;
    _finished = 0;
  }

  /// Counts [load]: asked for now, arrived when it completes either way.
  /// Returns [load] itself, so its caller still hears of a failure.
  Future<T> track<T>(Future<T> load) {
    final round = _round;
    _started++;
    void arrived() {
      if (round == _round) _finished++;
    }

    load.then<void>((_) => arrived(), onError: (Object _) => arrived());
    return load;
  }
}
