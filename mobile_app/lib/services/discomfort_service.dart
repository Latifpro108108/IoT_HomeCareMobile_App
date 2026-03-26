import 'package:flutter/foundation.dart';
import '../models/sensor_data_model.dart';
import '../models/threshold_model.dart';
import '../models/alert_model.dart';

class DiscomfortService {
  static const double _weightTemp     = 0.35;
  static const double _weightHumidity = 0.25;
  static const double _weightMotion   = 0.25;
  static const double _weightSound    = 0.15;

  static const double _warningThreshold = 0.40;

  int _consecutiveHighScoreCount = 0;
  static const int _requiredConsecutiveCount = 3;
  DateTime? _lastDiscomfortAlertAt;
  static const Duration _discomfortAlertCooldown = Duration(minutes: 3);

  DateTime? _stableStartAt;
  DateTime? _lastGoodConditionReportedAt;
  static const Duration _goodConditionWindow = Duration(minutes: 45);
  static const Duration _goodConditionCooldown = Duration(minutes: 45);

  AlertEvent? analyse({
    required SensorDataModel data,
    required ThresholdModel  thresholds,
  }) {
    final tempScore   = _temperatureScore(data.temperature, thresholds);
    final humScore    = _humidityScore(data.humidity, thresholds);
    final motionScore = _motionScore(data.motion.magnitude, thresholds);
    final soundScore  = _soundScore(data.sound.toDouble(), thresholds);

    double totalScore = (_weightTemp     * tempScore)   +
                        (_weightHumidity * humScore)    +
                        (_weightMotion   * motionScore) +
                        (_weightSound    * soundScore);

    totalScore = totalScore.clamp(0.0, 1.0);

    debugPrint(
      'DiscomfortService: temp=$tempScore hum=$humScore '
      'motion=$motionScore sound=$soundScore total=$totalScore',
    );

    final activeSensorCount = [
      tempScore > 0,
      humScore > 0,
      motionScore > 0,
      soundScore > 0,
    ].where((v) => v).length;
    final combinedAnomaly = activeSensorCount >= 2;
    final highCombinedScore = totalScore >= _warningThreshold && combinedAnomaly;

    if (highCombinedScore) {
      _consecutiveHighScoreCount++;
    } else {
      _consecutiveHighScoreCount = 0;
    }

    if (_consecutiveHighScoreCount < _requiredConsecutiveCount) return null;
    if (!highCombinedScore) return null;

    final now = DateTime.now();
    if (_lastDiscomfortAlertAt != null &&
        now.difference(_lastDiscomfortAlertAt!) < _discomfortAlertCooldown) {
      return null;
    }

    final indicators = <String, dynamic>{
      'discomfort_score': totalScore,
      'temp_score':       tempScore,
      'humidity_score':   humScore,
      'motion_score':     motionScore,
      'sound_score':      soundScore,
      'active_sensor_count': activeSensorCount,
      'temperature':      data.temperature,
      'humidity':         data.humidity,
      'motion_magnitude': data.motion.magnitude,
      'sound':            data.sound,
    };

    final message = _buildMessage(
      totalScore, tempScore, humScore, motionScore, soundScore,
      data, thresholds,
    );

    _lastDiscomfortAlertAt = now;
    _consecutiveHighScoreCount = 0;
    return AlertEvent(
      type:       AlertType.discomfort,
      confidence: totalScore,
      message:    message,
      indicators: indicators,
      detectedAt: now,
    );
  }

  AlertEvent? evaluateGoodCondition({
    required SensorDataModel data,
    required ThresholdModel thresholds,
  }) {
    final inRange =
        thresholds.tempInRange(data.temperature) &&
        thresholds.humidityInRange(data.humidity) &&
        thresholds.motionInRange(data.motion.magnitude) &&
        thresholds.soundInRange(data.sound.toDouble());

    final now = DateTime.now();
    if (!inRange) {
      _stableStartAt = null;
      return null;
    }

    _stableStartAt ??= now;
    final stableDuration = now.difference(_stableStartAt!);
    if (stableDuration < _goodConditionWindow) {
      return null;
    }

    if (_lastGoodConditionReportedAt != null &&
        now.difference(_lastGoodConditionReportedAt!) < _goodConditionCooldown) {
      return null;
    }

    _lastGoodConditionReportedAt = now;
    return AlertEvent(
      type: AlertType.normal,
      confidence: 1.0,
      message:
          'Readings stayed stable within comfort range for 45 minutes. Good condition.',
      indicators: {
        'stable_for_minutes': stableDuration.inMinutes,
        'temperature': data.temperature,
        'humidity': data.humidity,
        'motion_magnitude': data.motion.magnitude,
        'sound': data.sound,
      },
      detectedAt: now,
    );
  }

  List<ThresholdBreachDetail> checkThresholdBreaches({
    required SensorDataModel data,
    required ThresholdModel  thresholds,
  }) {
    final breaches = <ThresholdBreachDetail>[];

    if (!thresholds.tempInRange(data.temperature)) {
      breaches.add(ThresholdBreachDetail(
        sensorName:   'Temperature',
        currentValue: data.temperature,
        minValue:     thresholds.tempMin,
        maxValue:     thresholds.tempMax,
        unit:         '°C',
      ));
    }
    if (!thresholds.humidityInRange(data.humidity)) {
      breaches.add(ThresholdBreachDetail(
        sensorName:   'Humidity',
        currentValue: data.humidity,
        minValue:     thresholds.humidityMin,
        maxValue:     thresholds.humidityMax,
        unit:         '%',
      ));
    }
    if (!thresholds.motionInRange(data.motion.magnitude)) {
      breaches.add(ThresholdBreachDetail(
        sensorName:   'Motion',
        currentValue: data.motion.magnitude,
        minValue:     0.0,
        maxValue:     thresholds.motionMax,
        unit:         ' m/s²',
      ));
    }
    if (!thresholds.soundInRange(data.sound.toDouble())) {
      breaches.add(ThresholdBreachDetail(
        sensorName:   'Sound',
        currentValue: data.sound.toDouble(),
        minValue:     0.0,
        maxValue:     thresholds.soundMax,
        unit:         ' units',
      ));
    }

    return breaches;
  }

  void resetCounter() {
    _consecutiveHighScoreCount = 0;
    _stableStartAt = null;
  }

  double _temperatureScore(double temp, ThresholdModel t) {
    if (temp < t.tempMin) return ((t.tempMin - temp) / t.tempMin).clamp(0.0, 1.0);
    if (temp > t.tempMax) return ((temp - t.tempMax) / t.tempMax).clamp(0.0, 1.0);
    return 0.0;
  }

  double _humidityScore(double hum, ThresholdModel t) {
    if (hum < t.humidityMin) return ((t.humidityMin - hum) / t.humidityMin).clamp(0.0, 1.0);
    if (hum > t.humidityMax) return ((hum - t.humidityMax) / t.humidityMax).clamp(0.0, 1.0);
    return 0.0;
  }

  double _motionScore(double motion, ThresholdModel t) {
    if (motion <= t.motionMax) return 0.0;
    return ((motion - t.motionMax) / t.motionMax).clamp(0.0, 1.0);
  }

  double _soundScore(double sound, ThresholdModel t) {
    if (sound <= t.soundMax) return 0.0;
    return ((sound - t.soundMax) / t.soundMax).clamp(0.0, 1.0);
  }

  String _buildMessage(
    double totalScore,
    double tempScore,
    double humScore,
    double motionScore,
    double soundScore,
    SensorDataModel data,
    ThresholdModel thresholds,
  ) {
    final parts = <String>[];
    if (tempScore > 0) {
      final dir = data.temperature > thresholds.tempMax ? 'high' : 'low';
      parts.add('temperature too $dir (${data.temperature.toStringAsFixed(1)}°C)');
    }
    if (humScore > 0) {
      final dir = data.humidity > thresholds.humidityMax ? 'high' : 'low';
      parts.add('humidity too $dir (${data.humidity.toStringAsFixed(1)}%)');
    }
    if (motionScore > 0) {
      parts.add('elevated motion (${data.motion.magnitude.toStringAsFixed(2)} m/s²)');
    }
    if (soundScore > 0) {
      parts.add('loud environment (${data.sound} units)');
    }
    final confidence = (totalScore * 100).toInt();
    if (parts.isEmpty) return 'Possible discomfort detected ($confidence% confidence)';
    return 'Possible discomfort: ${parts.join(', ')} — $confidence% confidence';
  }
}