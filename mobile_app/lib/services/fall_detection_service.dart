import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/sensor_data_model.dart';
import '../models/event_model.dart';
import '../models/alert_model.dart';
import 'event_service.dart';
import 'notification_service.dart';

class FallDetectionService {
  final EventService _eventService;
  final NotificationService _notificationService;

  // Sliding window for statistical analysis (last N readings)
  final List<SensorDataModel> _recentReadings = [];
  final List<DateTime> _readingTimestamps = [];
  static const int _windowSize = 15; // Reduced for faster detection

  DateTime? _lastFallDetection;
  SensorDataModel? _previousReading;
  static const int _fallDetectionCooldownSeconds = 15; // Reduced cooldown

  FallDetectionService(this._eventService, this._notificationService);

  /// Improved fall detection using statistical analysis
  /// Algorithm uses:
  /// - Rolling mean and standard deviation
  /// - Z-score analysis (outlier detection)
  /// - Velocity and acceleration changes
  /// - Multi-factor confidence scoring with improved thresholds
  Future<EventModel?> analyzeSensorDataForFall({
    required String userId,
    required String deviceId,
    required SensorDataModel currentData,
    SensorDataModel? previousData,
  }) async {
    // Check cooldown
    if (_lastFallDetection != null &&
        DateTime.now().difference(_lastFallDetection!).inSeconds <
            _fallDetectionCooldownSeconds) {
      return null;
    }

    // Add current reading to sliding window
    _recentReadings.add(currentData);
    _readingTimestamps.add(DateTime.now());

    // Keep window size manageable
    if (_recentReadings.length > _windowSize) {
      _recentReadings.removeAt(0);
      _readingTimestamps.removeAt(0);
    }

    // Need at least 5 readings for statistical analysis
    if (_recentReadings.length < 5) {
      return null;
    }

    // Calculate statistical metrics
    final stats = _calculateStatistics(_recentReadings);
    final velocityMetrics =
        _calculateVelocityMetrics(_recentReadings, _readingTimestamps);

    // Analyze current reading against statistical baseline
    final analysis = _analyzeFallIndicators(
      currentData,
      stats,
      velocityMetrics,
      previousData,
    );

    // Improved confidence threshold (lowered to 0.55 for better detection)
    if (analysis.confidence >= 0.55) {
      final event = EventModel(
        id: _eventService.generateEventId(),
        userId: userId,
        deviceId: deviceId,
        type: EventType.fall,
        confidence: analysis.confidence.clamp(0.0, 1.0),
        sensorData: {
          'motion_magnitude': currentData.motion.magnitude,
          'sound': currentData.sound,
          'angle_x': currentData.motion.angleX,
          'angle_y': currentData.motion.angleY,
          'angle_z': currentData.motion.angleZ,
        },
        additionalData: {
          'algorithm': 'statistical_analysis_improved',
          'description': analysis.description,
          'z_score_motion': stats.stdDevMotion > 0
              ? ((currentData.motion.magnitude - stats.meanMotion).abs() /
                  stats.stdDevMotion)
              : 0.0,
          'z_score_sound': stats.stdDevSound > 0
              ? ((currentData.sound.toDouble() - stats.meanSound).abs() /
                  stats.stdDevSound)
              : 0.0,
          'mean_motion': stats.meanMotion,
          'std_dev_motion': stats.stdDevMotion,
          'mean_sound': stats.meanSound,
          'std_dev_sound': stats.stdDevSound,
          'acceleration_angle': velocityMetrics.accelerationAngle,
          'acceleration_motion': velocityMetrics.accelerationMotion,
        },
        timestamp: DateTime.now(),
      );

      // Save event and send notification IMMEDIATELY (critical event)
      await _eventService.saveEvent(event);
      await _notificationService.showFallAlert(
        AlertEvent(
          type: AlertType.fall,
          confidence: event.confidence,
          message: analysis.description,
          indicators: event.sensorData,
          detectedAt: event.timestamp,
        ),
      );

      _lastFallDetection = DateTime.now();
      debugPrint(
          '🚨 FALL DETECTED! Confidence: ${(analysis.confidence * 100).toStringAsFixed(1)}%');
      debugPrint('   Indicators: ${analysis.description}');

      return event;
    }

    return null;
  }

  // Backward-compatible helper used by older screens.
  Future<AlertEvent?> checkForFall({
    required SensorDataModel data,
    required String userId,
    required String deviceId,
  }) async {
    final event = await analyzeSensorDataForFall(
      userId: userId,
      deviceId: deviceId,
      currentData: data,
      previousData: _previousReading,
    );
    _previousReading = data;

    if (event == null) return null;
    return AlertEvent(
      type: AlertType.fall,
      confidence: event.confidence,
      message:
          event.additionalData?['description']?.toString() ?? 'Fall detected',
      indicators: event.sensorData,
      detectedAt: event.timestamp,
    );
  }

  // Backward-compatible helper used by monitoring screen.
  Future<List<Map<String, dynamic>>> fetchFallHistory({
    required String deviceId,
    int limit = 50,
  }) async {
    final events =
        await _eventService.fetchFallEventsForDevice(deviceId, limit: limit);
    return events
        .map(
          (e) => <String, dynamic>{
            'confidence': e.confidence,
            'timestamp': e.timestamp.millisecondsSinceEpoch,
          },
        )
        .toList();
  }

  _StatisticalMetrics _calculateStatistics(List<SensorDataModel> readings) {
    if (readings.isEmpty) {
      return _StatisticalMetrics.empty();
    }

    // Motion Magnitude
    final motionValues = readings.map((r) => r.motion.magnitude).toList();
    final meanMotion =
        motionValues.reduce((a, b) => a + b) / motionValues.length;
    final motionVariance = motionValues
            .map((x) => pow(x - meanMotion, 2))
            .reduce((a, b) => a + b) /
        motionValues.length;
    final stdDevMotion = sqrt(motionVariance);

    // Sound Levels
    final soundValues = readings.map((r) => r.sound.toDouble()).toList();
    final meanSound = soundValues.reduce((a, b) => a + b) / soundValues.length;
    final soundVariance =
        soundValues.map((x) => pow(x - meanSound, 2)).reduce((a, b) => a + b) /
            soundValues.length;
    final stdDevSound = sqrt(soundVariance);

    // Angles
    final angleXValues = readings.map((r) => r.motion.angleX).toList();
    final meanAngleX =
        angleXValues.reduce((a, b) => a + b) / angleXValues.length;
    final angleXVariance = angleXValues
            .map((x) => pow(x - meanAngleX, 2))
            .reduce((a, b) => a + b) /
        angleXValues.length;
    final stdDevAngleX = sqrt(angleXVariance);

    final angleYValues = readings.map((r) => r.motion.angleY).toList();
    final meanAngleY =
        angleYValues.reduce((a, b) => a + b) / angleYValues.length;
    final angleYVariance = angleYValues
            .map((x) => pow(x - meanAngleY, 2))
            .reduce((a, b) => a + b) /
        angleYValues.length;
    final stdDevAngleY = sqrt(angleYVariance);

    final angleZValues = readings.map((r) => r.motion.angleZ).toList();
    final meanAngleZ =
        angleZValues.reduce((a, b) => a + b) / angleZValues.length;
    final angleZVariance = angleZValues
            .map((x) => pow(x - meanAngleZ, 2))
            .reduce((a, b) => a + b) /
        angleZValues.length;
    final stdDevAngleZ = sqrt(angleZVariance);

    return _StatisticalMetrics(
      meanMotion: meanMotion,
      stdDevMotion: stdDevMotion,
      meanSound: meanSound,
      stdDevSound: stdDevSound,
      meanAngleX: meanAngleX,
      stdDevAngleX: stdDevAngleX,
      meanAngleY: meanAngleY,
      stdDevAngleY: stdDevAngleY,
      meanAngleZ: meanAngleZ,
      stdDevAngleZ: stdDevAngleZ,
    );
  }

  _VelocityMetrics _calculateVelocityMetrics(
      List<SensorDataModel> readings, List<DateTime> timestamps) {
    if (readings.length < 2) {
      return _VelocityMetrics.empty();
    }

    // Calculate change rates (velocity) for recent readings
    final recentCount = min(5, readings.length);
    double totalAngleVelocityX = 0;
    double totalAngleVelocityY = 0;
    double totalAngleVelocityZ = 0;
    double totalMotionVelocity = 0;
    int validPairs = 0;

    for (int i = readings.length - recentCount; i < readings.length - 1; i++) {
      final timeDiff =
          timestamps[i + 1].difference(timestamps[i]).inMilliseconds / 1000.0;
      if (timeDiff > 0 && timeDiff < 5.0) {
        // Ignore very large time gaps
        final angleVelX =
            (readings[i + 1].motion.angleX - readings[i].motion.angleX).abs() /
                timeDiff;
        final angleVelY =
            (readings[i + 1].motion.angleY - readings[i].motion.angleY).abs() /
                timeDiff;
        final angleVelZ =
            (readings[i + 1].motion.angleZ - readings[i].motion.angleZ).abs() /
                timeDiff;
        final motionVel =
            (readings[i + 1].motion.magnitude - readings[i].motion.magnitude)
                    .abs() /
                timeDiff;

        totalAngleVelocityX += angleVelX;
        totalAngleVelocityY += angleVelY;
        totalAngleVelocityZ += angleVelZ;
        totalMotionVelocity += motionVel;
        validPairs++;
      }
    }

    final meanAngleVelX =
        validPairs > 0 ? totalAngleVelocityX / validPairs : 0.0;
    final meanAngleVelY =
        validPairs > 0 ? totalAngleVelocityY / validPairs : 0.0;
    final meanAngleVelZ =
        validPairs > 0 ? totalAngleVelocityZ / validPairs : 0.0;
    final meanMotionVel =
        validPairs > 0 ? totalMotionVelocity / validPairs : 0.0;

    // Calculate acceleration (change in velocity)
    double accelerationAngle = 0.0;
    double accelerationMotion = 0.0;

    if (readings.length >= 3 && timestamps.length >= 3) {
      final lastIndex = readings.length - 1;
      final midIndex = readings.length - 2;

      final time1 = timestamps[lastIndex]
              .difference(timestamps[midIndex])
              .inMilliseconds /
          1000.0;
      final time2 = timestamps[midIndex]
              .difference(timestamps[midIndex - 1])
              .inMilliseconds /
          1000.0;

      if (time1 > 0 && time2 > 0 && time1 < 5.0 && time2 < 5.0) {
        final vel1Angle = ((readings[lastIndex].motion.angleX -
                        readings[midIndex].motion.angleX)
                    .abs() +
                (readings[lastIndex].motion.angleY -
                        readings[midIndex].motion.angleY)
                    .abs() +
                (readings[lastIndex].motion.angleZ -
                        readings[midIndex].motion.angleZ)
                    .abs()) /
            3 /
            time1;
        final vel2Angle = ((readings[midIndex].motion.angleX -
                        readings[midIndex - 1].motion.angleX)
                    .abs() +
                (readings[midIndex].motion.angleY -
                        readings[midIndex - 1].motion.angleY)
                    .abs() +
                (readings[midIndex].motion.angleZ -
                        readings[midIndex - 1].motion.angleZ)
                    .abs()) /
            3 /
            time2;
        final vel1Motion = (readings[lastIndex].motion.magnitude -
                    readings[midIndex].motion.magnitude)
                .abs() /
            time1;
        final vel2Motion = (readings[midIndex].motion.magnitude -
                    readings[midIndex - 1].motion.magnitude)
                .abs() /
            time2;

        accelerationAngle =
            ((vel1Angle - vel2Angle).abs() / time1).clamp(0.0, 1000.0);
        accelerationMotion =
            ((vel1Motion - vel2Motion).abs() / time1).clamp(0.0, 100.0);
      }
    }

    return _VelocityMetrics(
      meanAngleVelocityX: meanAngleVelX,
      meanAngleVelocityY: meanAngleVelY,
      meanAngleVelocityZ: meanAngleVelZ,
      meanMotionVelocity: meanMotionVel,
      accelerationAngle: accelerationAngle,
      accelerationMotion: accelerationMotion,
    );
  }

  /// Analyze fall indicators using improved statistical methods
  _FallAnalysis _analyzeFallIndicators(
    SensorDataModel current,
    _StatisticalMetrics stats,
    _VelocityMetrics velocity,
    SensorDataModel? previous,
  ) {
    double confidence = 0.0;
    final indicators = <String>[];

    // 1. Z-Score Analysis (improved thresholds)
    final zScoreMotion = stats.stdDevMotion > 0
        ? (current.motion.magnitude - stats.meanMotion).abs() /
            stats.stdDevMotion
        : 0.0;
    final zScoreSound = stats.stdDevSound > 0
        ? (current.sound.toDouble() - stats.meanSound).abs() / stats.stdDevSound
        : 0.0;
    final zScoreAngleX = stats.stdDevAngleX > 0
        ? (current.motion.angleX - stats.meanAngleX).abs() / stats.stdDevAngleX
        : 0.0;
    final zScoreAngleY = stats.stdDevAngleY > 0
        ? (current.motion.angleY - stats.meanAngleY).abs() / stats.stdDevAngleY
        : 0.0;
    final zScoreAngleZ = stats.stdDevAngleZ > 0
        ? (current.motion.angleZ - stats.meanAngleZ).abs() / stats.stdDevAngleZ
        : 0.0;

    final maxZScore = max(
        max(max(max(zScoreMotion, zScoreSound), zScoreAngleX), zScoreAngleY),
        zScoreAngleZ);

    // Improved z-score weighting
    if (maxZScore >= 2.5) {
      confidence += 0.30; // 2.5+ sigma = very significant
      indicators.add(
          'Statistical outlier (z-score: ${maxZScore.toStringAsFixed(2)})');
    } else if (maxZScore >= 2.0) {
      confidence += 0.20; // 2-2.5 sigma = significant
      indicators.add(
          'Statistical outlier (z-score: ${maxZScore.toStringAsFixed(2)})');
    } else if (maxZScore >= 1.5) {
      confidence += 0.10; // 1.5-2 sigma = moderate
      indicators
          .add('Moderate outlier (z-score: ${maxZScore.toStringAsFixed(2)})');
    }

    // 2. Sudden Motion Magnitude Increase (improved threshold)
    if (current.motion.magnitude >
        stats.meanMotion + 1.5 * stats.stdDevMotion) {
      confidence += 0.25;
      indicators.add(
          'High motion (${current.motion.magnitude.toStringAsFixed(2)} vs ${stats.meanMotion.toStringAsFixed(2)})');
    }

    // 3. Sudden Sound Spike (improved threshold)
    if (current.sound > stats.meanSound + 1.5 * stats.stdDevSound) {
      confidence += 0.20;
      indicators.add(
          'Sound spike (${current.sound.toInt()} vs ${stats.meanSound.toInt()})');
    }

    // 4. Rapid Angle Change (improved thresholds)
    final maxAngleVelocity = max(
        max(velocity.meanAngleVelocityX, velocity.meanAngleVelocityY),
        velocity.meanAngleVelocityZ);
    if (maxAngleVelocity > 30) {
      // Lowered from 50
      confidence += 0.20;
      indicators.add(
          'Rapid angle change (${maxAngleVelocity.toStringAsFixed(1)}°/s)');
    }

    // 5. High Acceleration (improved thresholds)
    if (velocity.accelerationAngle > 50) {
      // Lowered from 100
      confidence += 0.20;
      indicators.add(
          'High angular acceleration (${velocity.accelerationAngle.toStringAsFixed(1)}°/s²)');
    }

    if (velocity.accelerationMotion > 2.5) {
      // Lowered from 5
      confidence += 0.15;
      indicators.add(
          'High motion acceleration (${velocity.accelerationMotion.toStringAsFixed(2)} m/s³)');
    }

    // 6. Comparison with previous reading (if available)
    if (previous != null) {
      final angleChange = max(
        max(
          (current.motion.angleX - previous.motion.angleX).abs(),
          (current.motion.angleY - previous.motion.angleY).abs(),
        ),
        (current.motion.angleZ - previous.motion.angleZ).abs(),
      );

      if (angleChange > 30) {
        // Lowered from 45
        confidence += 0.20;
        indicators
            .add('Sudden angle change (${angleChange.toStringAsFixed(1)}°)');
      }
    }

    // Build description
    final description = indicators.isEmpty
        ? 'Fall detected based on statistical analysis'
        : indicators.join(', ');

    return _FallAnalysis(confidence: confidence, description: description);
  }

  void reset() {
    _recentReadings.clear();
    _readingTimestamps.clear();
    _lastFallDetection = null;
  }
}

/// Statistical metrics for the sliding window
class _StatisticalMetrics {
  final double meanMotion;
  final double meanSound;
  final double meanAngleX;
  final double meanAngleY;
  final double meanAngleZ;
  final double stdDevMotion;
  final double stdDevSound;
  final double stdDevAngleX;
  final double stdDevAngleY;
  final double stdDevAngleZ;

  _StatisticalMetrics({
    required this.meanMotion,
    required this.meanSound,
    required this.meanAngleX,
    required this.meanAngleY,
    required this.meanAngleZ,
    required this.stdDevMotion,
    required this.stdDevSound,
    required this.stdDevAngleX,
    required this.stdDevAngleY,
    required this.stdDevAngleZ,
  });

  factory _StatisticalMetrics.empty() {
    return _StatisticalMetrics(
      meanMotion: 0,
      meanSound: 0,
      meanAngleX: 0,
      meanAngleY: 0,
      meanAngleZ: 0,
      stdDevMotion: 0,
      stdDevSound: 0,
      stdDevAngleX: 0,
      stdDevAngleY: 0,
      stdDevAngleZ: 0,
    );
  }
}

/// Velocity and acceleration metrics
class _VelocityMetrics {
  final double meanAngleVelocityX;
  final double meanAngleVelocityY;
  final double meanAngleVelocityZ;
  final double meanMotionVelocity;
  final double accelerationAngle;
  final double accelerationMotion;

  _VelocityMetrics({
    required this.meanAngleVelocityX,
    required this.meanAngleVelocityY,
    required this.meanAngleVelocityZ,
    required this.meanMotionVelocity,
    required this.accelerationAngle,
    required this.accelerationMotion,
  });

  factory _VelocityMetrics.empty() {
    return _VelocityMetrics(
      meanAngleVelocityX: 0,
      meanAngleVelocityY: 0,
      meanAngleVelocityZ: 0,
      meanMotionVelocity: 0,
      accelerationAngle: 0,
      accelerationMotion: 0,
    );
  }
}

/// Fall analysis result
class _FallAnalysis {
  final double confidence;
  final String description;

  _FallAnalysis({
    required this.confidence,
    required this.description,
  });
}
