/// Snapshot from iOS CoreMotion (CMMotionActivity).
class MotionSample {
  const MotionSample({
    this.automotive = false,
    this.stationary = false,
    this.walking = false,
    this.running = false,
    this.cycling = false,
    this.confidence = 0,
  });

  factory MotionSample.fromMap(Map<dynamic, dynamic> m) => MotionSample(
    automotive: m['automotive'] == true,
    stationary: m['stationary'] == true,
    walking: m['walking'] == true,
    running: m['running'] == true,
    cycling: m['cycling'] == true,
    confidence: (m['confidence'] as num?)?.toInt() ?? 0,
  );

  final bool automotive;
  final bool stationary;
  final bool walking;
  final bool running;
  final bool cycling;

  /// 0 = low, 1 = medium, 2 = high.
  final int confidence;

  bool get onFoot => (walking || running) && confidence >= 1;
}

enum DrivingState { unknown, driving, stopped }

/// Fuses GPS speed and CoreMotion activity into a driving / stopped state.
///
/// Safety-first hysteresis:
///  * Enter **driving** as soon as GPS speed exceeds [drivingSpeed] or
///    CoreMotion reports automotive motion with medium+ confidence.
///  * Leave driving only when the user is clearly on foot, or after the
///    vehicle has been still for [stopDwell] — so a red light or a
///    traffic jam does not unlock the Submit button.
class DrivingDetector {
  DrivingDetector({
    this.drivingSpeed = 6.7, // ≈15 mph
    this.stillSpeed = 1.5, // ≈3 mph
    this.stopDwell = const Duration(seconds: 45),
  });

  final double drivingSpeed;
  final double stillSpeed;
  final Duration stopDwell;

  DrivingState _state = DrivingState.unknown;
  DateTime? _stillSince;
  double? _speed;
  MotionSample? _motion;

  DrivingState get state => _state;
  double? get speed => _speed;
  MotionSample? get motion => _motion;

  /// Seconds remaining until a still vehicle counts as stopped, or null.
  int? secondsUntilStopped(DateTime now) {
    if (_state != DrivingState.driving || _stillSince == null) return null;
    final left = stopDwell - now.difference(_stillSince!);
    return left.isNegative ? 0 : left.inSeconds;
  }

  DrivingState onSpeed(double? metersPerSecond, DateTime now) {
    // CoreLocation reports -1 when speed is unknown.
    _speed = (metersPerSecond == null || metersPerSecond < 0)
        ? null
        : metersPerSecond;
    return _evaluate(now);
  }

  DrivingState onMotion(MotionSample sample, DateTime now) {
    _motion = sample;
    return _evaluate(now);
  }

  /// Re-evaluate on a timer so dwell time can elapse without new samples.
  DrivingState tick(DateTime now) => _evaluate(now);

  DrivingState _evaluate(DateTime now) {
    final speed = _speed;
    final m = _motion;
    final movingFast = speed != null && speed >= drivingSpeed;
    final motionSaysDriving =
        m != null && m.automotive && !m.stationary && m.confidence >= 1;
    final still =
        (speed != null && speed < stillSpeed) ||
        (speed == null && m != null && m.stationary);

    if (m != null && m.onFoot && !movingFast) {
      _stillSince = null;
      return _state = DrivingState.stopped;
    }

    if (movingFast || (motionSaysDriving && !still)) {
      _stillSince = null;
      return _state = DrivingState.driving;
    }

    if (_state == DrivingState.driving) {
      if (still) {
        _stillSince ??= now;
        if (now.difference(_stillSince!) >= stopDwell) {
          _stillSince = null;
          return _state = DrivingState.stopped;
        }
      } else {
        _stillSince = null;
      }
      return _state;
    }

    if (still || (m != null && !m.automotive && m.confidence >= 1)) {
      return _state = DrivingState.stopped;
    }
    return _state;
  }
}
