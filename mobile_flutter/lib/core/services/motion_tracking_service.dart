import 'dart:async';
import 'dart:io' show Platform;

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
  static const _goalNotifiedDateKey = 'goal_notified_date';

  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<Position>? _positionSubscription;
  ApiService? _api;
  double _latestSpeedMps = 0;
  bool _started = false;

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
    final settingsRes = await _api!.fetchSettings();
    final settings = (settingsRes['settings'] as Map).cast<String, dynamic>();
    final automation = (settings['automation'] as Map?)?.cast<String, dynamic>() ?? {};
    final permissions = (settings['permissions'] as Map?)?.cast<String, dynamic>() ?? {};
    final enabled = automation['autoStepTracking'] == true && permissions['location'] == true && permissions['activity'] == true;

    if (!enabled) {
      await _stopStreams();
      return;
    }

    final granted = await _ensurePermissions();
    if (!granted) {
      await _stopStreams();
      return;
    }

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
    ).listen((position) {
      _latestSpeedMps = position.speed.isFinite && position.speed >= 0 ? position.speed : 0;
    });

    _stepSubscription ??= Pedometer.stepCountStream.listen(_handleStepEvent);
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
    if (_latestSpeedMps > _walkingSpeedUpperBound) return;

    final summary = await api.logSteps(delta, source: 'sensor');
    final stepSummary = (summary['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final progress = (stepSummary['progress'] as num?)?.toInt() ?? 0;
    if (progress >= 100) {
      final notifiedDate = prefs.getString(_goalNotifiedDateKey);
      if (notifiedDate != today) {
        await NotificationService.instance.show(
          id: today.hashCode,
          title: 'Goal Achieved',
          body: 'Great work. You reached your daily step goal.',
        );
        await prefs.setString(_goalNotifiedDateKey, today);
      }
    }
  }

  Future<bool> _ensurePermissions() async {
    var locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied || locationPermission == LocationPermission.deniedForever) {
      locationPermission = await Geolocator.requestPermission();
    }

    final activityPermission = await Permission.activityRecognition.request();

    final locationGranted = locationPermission == LocationPermission.always || locationPermission == LocationPermission.whileInUse;
    return locationGranted && activityPermission.isGranted;
  }

  Future<void> _stopStreams() async {
    await _stepSubscription?.cancel();
    await _positionSubscription?.cancel();
    _stepSubscription = null;
    _positionSubscription = null;
  }
}
