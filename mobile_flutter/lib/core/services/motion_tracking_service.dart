import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'notification_service.dart';

class MotionTrackingService {
  MotionTrackingService._();

  static final MotionTrackingService instance = MotionTrackingService._();

  static const _lastRawStepKey = 'motion_last_raw_steps';
  static const _lastRawStepDateKey = 'motion_last_raw_steps_date';
  static const _dismissedUpdateVersionKey = 'dismissed_update_version';
  static const _walkingSpeedUpperBound = 2.6;
  static const _walkingSpeedLowerBound = 0.35;
  static const _goalNotifiedDateKey = 'goal_notified_date';

  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianSubscription;
  StreamSubscription<Position>? _positionSubscription;
  ApiService? _api;
  double _latestSpeedMps = 0;
  String _latestPedestrianStatus = 'unknown';
  bool _started = false;
  Position? _lastTrackedPosition;
  DateTime? _lastTrackedAt;

  String get dismissedUpdateVersionKey => _dismissedUpdateVersionKey;

  Future<void> start(ApiService api) async {
    _api = api;
    if (_started) {
      await refreshConfig();
      return;
    }
    _started = true;
    await refreshConfig();
  }

  Future<void> refreshConfig() async {
    if (_api == null) return;
    try {
      final settingsRes = await _api!.fetchSettings();
      final settings = (settingsRes['settings'] as Map).cast<String, dynamic>();
      final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
      final permissions = (settings['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
      final autoTrackingEnabled = automation['autoStepTracking'] == true;
      final activityEnabled = permissions['activity'] == true;
      final locationEnabled = permissions['location'] == true;

      if (!autoTrackingEnabled || !activityEnabled) {
        await _stopStreams();
        return;
      }

      final granted = await _ensurePermissions(requireLocation: locationEnabled);
      if (!granted) {
        await _stopStreams();
        return;
      }

      if (locationEnabled) {
        _positionSubscription ??= Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 8,
                  intervalDuration: const Duration(seconds: 8),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.best,
                  distanceFilter: 8,
                ),
        ).listen((position) async {
          _latestSpeedMps = position.speed.isFinite && position.speed >= 0 ? position.speed : 0;
          await _handlePositionFallback(position);
        });
      } else {
        await _positionSubscription?.cancel();
        _positionSubscription = null;
        _latestSpeedMps = 0;
        _lastTrackedPosition = null;
        _lastTrackedAt = null;
      }

      _pedestrianSubscription ??= Pedometer.pedestrianStatusStream.listen(
        (status) {
          _latestPedestrianStatus = status.status;
        },
        onError: (_) {
          _latestPedestrianStatus = 'unknown';
        },
        cancelOnError: false,
      );

      _stepSubscription ??= Pedometer.stepCountStream.listen(
        _handleStepEvent,
        onError: (_) {
          // Some devices do not expose the hardware step counter cleanly.
        },
        cancelOnError: false,
      );
    } catch (_) {
      await _stopStreams();
    }
  }

  Future<void> _handleStepEvent(StepCount event) async {
    final api = _api;
    if (api == null) return;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final lastDate = prefs.getString(_lastRawStepDateKey);
    final lastRawSteps = prefs.getInt(_lastRawStepKey);

    if (lastDate != today || lastRawSteps == null) {
      await prefs.setString(_lastRawStepDateKey, today);
      await prefs.setInt(_lastRawStepKey, event.steps);
      return;
    }

    final delta = event.steps - lastRawSteps;
    await prefs.setInt(_lastRawStepKey, event.steps);

    if (delta <= 0) return;
    if (_latestPedestrianStatus == 'stopped') return;
    if (_latestSpeedMps > _walkingSpeedUpperBound) return;

    final summary = await api.logSteps(delta, source: 'sensor');
    await _maybeNotifyGoal(summary, prefs, today);
  }

  Future<void> _handlePositionFallback(Position position) async {
    final api = _api;
    if (api == null) return;

    final previous = _lastTrackedPosition;
    final previousAt = _lastTrackedAt;
    final now = DateTime.now();
    _lastTrackedPosition = position;
    _lastTrackedAt = now;

    if (previous == null || previousAt == null) return;

    final distanceMeters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    final durationSeconds = math.max(1, now.difference(previousAt).inSeconds);
    final speedMps = position.speed.isFinite && position.speed >= 0
        ? position.speed
        : distanceMeters / durationSeconds;

    if (distanceMeters < 6) return;
    if (_latestPedestrianStatus == 'stopped' && speedMps < 1.4) return;
    if (speedMps < _walkingSpeedLowerBound || speedMps > _walkingSpeedUpperBound) return;

    final summary = await api.logSmartSteps(
      distanceMeters: double.parse(distanceMeters.toStringAsFixed(2)),
      durationSeconds: durationSeconds,
      speedMps: double.parse(speedMps.toStringAsFixed(2)),
      activityHint: 'walking',
    );
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    await _maybeNotifyGoal(summary, prefs, today);
  }

  Future<void> _maybeNotifyGoal(
    Map<String, dynamic> payload,
    SharedPreferences prefs,
    String today,
  ) async {
    final stepSummary = (payload['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final progress = (stepSummary['progress'] as num?)?.toInt() ?? 0;
    if (progress < 100) return;

    final notifiedDate = prefs.getString(_goalNotifiedDateKey);
    if (notifiedDate == today) return;

    await NotificationService.instance.show(
      id: today.hashCode,
      title: 'Goal Achieved',
      body: 'Great work. You reached your daily step goal.',
    );
    await prefs.setString(_goalNotifiedDateKey, today);
  }

  Future<bool> _ensurePermissions({required bool requireLocation}) async {
    LocationPermission locationPermission = LocationPermission.denied;
    if (requireLocation) {
      locationPermission = await Geolocator.checkPermission();
      if (locationPermission == LocationPermission.denied || locationPermission == LocationPermission.deniedForever) {
        locationPermission = await Geolocator.requestPermission();
      }
    }

    final activityPermission = await Permission.activityRecognition.request();

    final locationGranted = !requireLocation ||
        locationPermission == LocationPermission.always ||
        locationPermission == LocationPermission.whileInUse;
    return locationGranted && activityPermission.isGranted;
  }

  Future<void> _stopStreams() async {
    await _stepSubscription?.cancel();
    await _pedestrianSubscription?.cancel();
    await _positionSubscription?.cancel();
    _stepSubscription = null;
    _pedestrianSubscription = null;
    _positionSubscription = null;
    _latestSpeedMps = 0;
    _latestPedestrianStatus = 'unknown';
    _lastTrackedPosition = null;
    _lastTrackedAt = null;
  }
}
