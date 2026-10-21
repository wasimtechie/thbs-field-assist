import 'dart:async';
import 'dart:math';

/// Drives only confirmed, encrypted reports while the app is unlocked.
class OutboxPump {
  OutboxPump({
    required this.hasWork,
    required this.send,
    DateTime Function()? now,
    this.interval = const Duration(seconds: 5),
  }) : now = now ?? DateTime.now;
  final bool Function() hasWork;
  final Future<bool> Function() send;
  final DateTime Function() now;
  final Duration interval;
  Timer? _timer;
  bool _running = false;
  int _generation = 0, _failures = 0;
  DateTime? _next;
  void start() {
    _timer?.cancel();
    _generation++;
    _failures = 0;
    _next = null;
    _timer = Timer.periodic(interval, (_) => unawaited(flush()));
  }

  Future<void> flush({bool immediately = false}) async {
    if (_running ||
        !hasWork() ||
        !immediately && _next?.isAfter(now()) == true) {
      return;
    }
    final generation = _generation;
    _running = true;
    var success = false;
    try {
      success = await send();
    } catch (_) {
      /* The encrypted outbox is retained. */
    } finally {
      _running = false;
      if (generation == _generation) {
        _failures = success ? 0 : _failures + 1;
        _next = success
            ? null
            : now().add(
                Duration(
                  seconds: min(60, 5 * pow(2, min(_failures - 1, 4)).toInt()),
                ),
              );
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _generation++;
  }
}
