import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/baseline_model.dart';
import '../models/sensor_data_model.dart';
import '../models/emotional_state_model.dart';
import '../utils/constants.dart';

class BaselineService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Initialize baseline for a condition (set to zero values)
  Future<void> initializeBaseline({
    required String userId,
    required String deviceId,
    required String condition,
  }) async {
    try {
      if (!AppConstants.baselineConditions.contains(condition)) {
        throw 'Invalid condition: $condition';
      }

      final initialBaseline = BaselineModel(
        userId: userId,
        deviceId: deviceId,
        condition: condition,
        sensorValues: {
          'temperature': 0.0,
          'humidity': 0.0,
          'motion_magnitude': 0.0,
          'motion_x': 0.0,
          'motion_y': 0.0,
          'motion_z': 0.0,
          'sound': 0,
        },
        recordedAt: DateTime.now(),
        notes: 'Initial zero baseline',
      );

      final docId = '${userId}_${deviceId}_$condition';
      // Firestore with timeout - don't block
      await _firestore
          .collection(AppConstants.baselinesCollection)
          .doc(docId)
          .set({
        ...initialBaseline.toJson(),
        'deviceId': deviceId,
      }).timeout(const Duration(seconds: 3));
      debugPrint('✅ Initial baseline set to Firestore: /${AppConstants.baselinesCollection}/$docId');
    } catch (e) {
      debugPrint('❌ Error initializing baseline: ${e.toString()}');
      // Don't throw - allow app to continue
      debugPrint('⚠️ Continuing without Firestore baseline storage');
    }
  }

  // Record baseline from current sensor data
  Future<void> recordBaseline({
    required String userId,
    required String deviceId,
    required String condition,
    required SensorDataModel sensorData,
    String? notes,
  }) async {
    try {
      if (!AppConstants.baselineConditions.contains(condition)) {
        throw 'Invalid condition: $condition';
      }

      final baseline = BaselineModel(
        userId: userId,
        deviceId: deviceId,
        condition: condition,
        sensorValues: {
          'temperature': sensorData.temperature,
          'humidity': sensorData.humidity,
          'motion_magnitude': sensorData.motion.magnitude,
          'motion_x': sensorData.motion.x,
          'motion_y': sensorData.motion.y,
          'motion_z': sensorData.motion.z,
          'sound': sensorData.sound,
        },
        recordedAt: DateTime.now(),
        notes: notes,
      );

      final docId = '${userId}_${deviceId}_$condition';
      // Firestore with timeout
      await _firestore
          .collection(AppConstants.baselinesCollection)
          .doc(docId)
          .set({
        ...baseline.toJson(),
        'deviceId': deviceId,
      }).timeout(const Duration(seconds: 3));
      
      debugPrint('✅ Baseline saved to Firestore: /${AppConstants.baselinesCollection}/$docId');
    } catch (e) {
      debugPrint('❌ Error recording baseline: ${e.toString()}');
      // Don't throw - allow app to continue
      debugPrint('⚠️ Baseline recording failed but continuing');
    }
  }

  // Get baseline for a condition and device
  Future<BaselineModel?> getBaseline({
    required String userId,
    required String deviceId,
    required String condition,
  }) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.baselinesCollection)
          .doc('${userId}_${deviceId}_$condition')
          .get()
          .timeout(const Duration(seconds: 2));

      if (doc.exists && doc.data() != null) {
        return BaselineModel.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting baseline (non-critical): ${e.toString()}');
      return null;
    }
  }

  // Check if baseline exists for a condition and device
  Future<bool> hasBaseline({
    required String userId,
    required String deviceId,
    required String condition,
  }) async {
    try {
      final doc = await _firestore
          .collection(AppConstants.baselinesCollection)
          .doc('${userId}_${deviceId}_$condition')
          .get()
          .timeout(const Duration(seconds: 2));

      if (!doc.exists || doc.data() == null) return false;

      final baseline = BaselineModel.fromJson(doc.data()!);
      return !baseline.isEmpty;
    } catch (e) {
      debugPrint('❌ Error checking baseline (non-critical): ${e.toString()}');
      return false;
    }
  }

  // Analyze sensor data against baseline using improved statistical methods
  EmotionalStateResult analyzeEmotionalState({
    required SensorDataModel currentData,
    required BaselineModel? baseline,
    String? targetCondition,
  }) {
    if (baseline == null || baseline.isEmpty) {
      return EmotionalStateResult(
        state: EmotionalState.unknown,
        confidence: 0.0,
        indicators: {},
        detectedAt: DateTime.now(),
      );
    }

    final indicators = <String, dynamic>{};
    
    // Get baseline values
    final baselineTemp = (baseline.sensorValues['temperature'] ?? 0.0) as num;
    final baselineHumidity = (baseline.sensorValues['humidity'] ?? 0.0) as num;
    final baselineMotion = (baseline.sensorValues['motion_magnitude'] ?? 0.0) as num;
    final baselineSound = (baseline.sensorValues['sound'] ?? 0) as num;

    // Calculate deviations and z-scores (using percentage-based thresholds)
    double totalDeviation = 0.0;
    int significantMetrics = 0;

    // Temperature deviation (using percentage-based threshold)
    final tempDiff = currentData.temperature - baselineTemp.toDouble();
    final tempDeviationPercent = baselineTemp.toDouble() > 0 
        ? (tempDiff.abs() / baselineTemp.toDouble()) * 100 
        : tempDiff.abs();
    
    if (tempDeviationPercent > 5) { // 5% threshold
      indicators['temperature_deviation'] = tempDeviationPercent.toStringAsFixed(1) + '%';
      indicators['temperature_absolute'] = tempDiff.abs().toStringAsFixed(2) + '°C';
      totalDeviation += tempDeviationPercent / 10; // Normalize
      significantMetrics++;
    }

    // Humidity deviation
    final humidityDiff = currentData.humidity - baselineHumidity.toDouble();
    final humidityDeviationPercent = baselineHumidity.toDouble() > 0
        ? (humidityDiff.abs() / baselineHumidity.toDouble()) * 100
        : humidityDiff.abs();
    
    if (humidityDeviationPercent > 10) { // 10% threshold
      indicators['humidity_deviation'] = humidityDeviationPercent.toStringAsFixed(1) + '%';
      indicators['humidity_absolute'] = humidityDiff.abs().toStringAsFixed(1) + '%';
      totalDeviation += humidityDeviationPercent / 20; // Normalize
      significantMetrics++;
    }

    // Motion deviation
    final motionDiff = currentData.motion.magnitude - baselineMotion.toDouble();
    final motionDeviationPercent = baselineMotion.toDouble() > 0
        ? (motionDiff.abs() / baselineMotion.toDouble()) * 100
        : motionDiff.abs();
    
    if (motionDeviationPercent > 20 || motionDiff.abs() > 0.3) { // 20% or 0.3 m/s²
      indicators['motion_deviation'] = motionDeviationPercent.toStringAsFixed(1) + '%';
      indicators['motion_absolute'] = motionDiff.abs().toStringAsFixed(3) + ' m/s²';
      totalDeviation += motionDeviationPercent / 15; // Normalize
      significantMetrics++;
    }

    // Sound deviation
    final soundDiff = (currentData.sound - baselineSound.toInt()).abs();
    final soundDeviationPercent = baselineSound.toInt() > 0
        ? (soundDiff / baselineSound.toInt()) * 100
        : soundDiff;
    
    if (soundDeviationPercent > 30 || soundDiff > 40) { // 30% or 40 units
      indicators['sound_deviation'] = soundDeviationPercent.toStringAsFixed(1) + '%';
      indicators['sound_absolute'] = soundDiff.toString();
      totalDeviation += soundDeviationPercent / 25; // Normalize
      significantMetrics++;
    }

    // Determine state and confidence based on deviations
    EmotionalState detectedState = EmotionalState.normal;
    double confidence = 0.0;

    if (significantMetrics > 0) {
      // Calculate average normalized deviation
      final avgDeviation = totalDeviation / significantMetrics;
      
      // Confidence increases with number of significant metrics and deviation magnitude
      confidence = min(avgDeviation / 3.0, 1.0); // Scale to 0-1
      confidence = confidence.clamp(0.0, 1.0);

      // Determine state based on target condition or predominant indicators
      if (targetCondition != null) {
        switch (targetCondition) {
          case 'anxiety':
            // Anxiety: High motion, sound, or temperature variations
            if (motionDeviationPercent > 25 || soundDeviationPercent > 40 || tempDeviationPercent > 8) {
              detectedState = EmotionalState.anxiety;
              confidence = min(confidence * 1.2, 1.0); // Boost confidence for target
            } else {
              detectedState = EmotionalState.unknown;
            }
            break;
          case 'stress':
            // Stress: High motion and humidity variations
            if (motionDeviationPercent > 30 || humidityDeviationPercent > 15) {
              detectedState = EmotionalState.stress;
              confidence = min(confidence * 1.2, 1.0);
            } else {
              detectedState = EmotionalState.unknown;
            }
            break;
          case 'discomfort':
            // Discomfort: High temperature or motion variations
            if (tempDeviationPercent > 10 || motionDeviationPercent > 25) {
              detectedState = EmotionalState.discomfort;
              confidence = min(confidence * 1.2, 1.0);
            } else {
              detectedState = EmotionalState.unknown;
            }
            break;
          default:
            detectedState = EmotionalState.unknown;
        }
      } else {
        // Auto-detect based on predominant indicators
        if (motionDeviationPercent > 30 || soundDeviationPercent > 50) {
          detectedState = EmotionalState.stress;
        } else if (tempDeviationPercent > 10) {
          detectedState = EmotionalState.discomfort;
        } else if (motionDeviationPercent > 20 || soundDeviationPercent > 40) {
          detectedState = EmotionalState.anxiety;
        } else {
          detectedState = EmotionalState.unknown;
        }
      }

      // Normal state if confidence is very low
      if (confidence < 0.3) {
        detectedState = EmotionalState.normal;
        confidence = 1.0 - confidence;
      }
    } else {
      // No significant deviations - normal state
      detectedState = EmotionalState.normal;
      confidence = 0.95; // High confidence in normal state
    }

    return EmotionalStateResult(
      state: detectedState,
      confidence: confidence.clamp(0.0, 1.0),
      indicators: indicators,
      detectedAt: DateTime.now(),
    );
  }
}
