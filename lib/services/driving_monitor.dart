import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'driving_detector.dart';

/// Demo override so the safety gate can be shown without a moving car.
enum DrivingOverride { auto, forceDriving, forceStopped }

/// Live driving status for the UI. Combines the GPS position stream with
/// CoreMotion activity updates from the native `clear_roads/motion_events`
/// channel (see ios/Runner/ClearRoadsNative.swift).
class DrivingMonitor extends ChangeNotifier {
  DrivingMonitor({DrivingDetector? detector})
    : _detector = detector ?? DrivingDetector();

  static const _motionEvents = EventChannel('clear_roads/motion_events');

  final DrivingDetector _detector;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<dynamic>? _motionSub;
  Timer? _ticker;

  DrivingOverride _override = DrivingOverride.auto;
  DrivingState _detected = DrivingState.unknown;
  Position? _lastPosition;
  bool _locationDenied = false;
  bool _motionAvailable = false;
  bool _started = false;

  DrivingOverride get overrideMode => _override;
  Position? get lastPosition => _lastPosition;
  bool get locationDenied => _locationDenied;
  bool get motionAvailable => _motionAvailable;
  double? get speedMps => _detector.speed;
  MotionSample? get motion => _detector.motion;
  int? get secondsUntilStopped => _detector.secondsUntilStopped(DateTime.now());

  DrivingState get state => switch (_override) {
    DrivingOverride.forceDriving => DrivingState.driving,
    DrivingOverride.forceStopped => DrivingState.stopped,
    DrivingOverride.auto => _detected,
  };

  bool get isDriving => state == DrivingState.driving;

  /// Submitting is only allowed once we're confident the user isn't driving.
  /// Unknown (e.g. no GPS fix yet) is treated as allowed only when location
  /// permission is denied — otherwise wait for the first reading.
  bool get canSubmit => switch (state) {
    DrivingState.driving => false,
    DrivingState.stopped => true,
    DrivingState.unknown => _locationDenied || !_started,
  };

  String get sourceLabel {
    if (_override != DrivingOverride.auto) return 'Demo override';
    final parts = <String>[
      if (_detector.speed != null)
        'GPS ${(_detector.speed! * 2.23694).round()} mph',
      if (_motionAvailable) 'Motion sensor',
    ];
    return parts.isEmpty ? 'Waiting for sensors' : parts.join(' · ');
  }

  void setOverride(DrivingOverride value) {
    _override = value;
    notifyListeners();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _motionSub = _motionEvents.receiveBroadcastStream().listen((event) {
      _motionAvailable = true;
      _apply(
        _detector.onMotion(MotionSample.fromMap(event as Map), DateTime.now()),
      );
    }, onError: (_) => _motionAvailable = false);

    await _startLocation();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      _apply(
        _detector.tick(DateTime.now()),
        force: _detected == DrivingState.driving,
      );
    });
  }

  Future<void> _startLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _locationDenied = true;
        notifyListeners();
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _locationDenied = true;
        notifyListeners();
        return;
      }
      _locationDenied = false;
      final settings = defaultTargetPlatform == TargetPlatform.iOS
          ? AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              activityType: ActivityType.automotiveNavigation,
              distanceFilter: 0,
              pauseLocationUpdatesAutomatically: false,
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
            )
          : const LocationSettings(accuracy: LocationAccuracy.high);
      await _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) {
            _lastPosition = p;
            _apply(_detector.onSpeed(p.speed, DateTime.now()), force: true);
          }, onError: (_) {});
    } catch (_) {
      _locationDenied = true;
      notifyListeners();
    }
  }

  /// Re-check permission after the user returns from Settings.
  Future<void> retryLocation() => _startLocation();

  void _apply(DrivingState s, {bool force = false}) {
    if (s != _detected || force) {
      _detected = s;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _motionSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
