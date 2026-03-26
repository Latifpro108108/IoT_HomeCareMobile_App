// threshold_model.dart
//
// Replaces BaselineModel entirely.
// Instead of auto-recording sensor baselines, the caregiver manually sets
// a comfort range (min + max) for each sensor. The system alerts when any
// smoothed reading leaves that range for a sustained period.

class ThresholdModel {
  final String userId;
  final String deviceId;
  final double tempMin;
  final double tempMax;
  final double humidityMin;
  final double humidityMax;
  final double motionMax;
  final double soundMax;
  final DateTime updatedAt;

  ThresholdModel({
    required this.userId,
    required this.deviceId,
    required this.tempMin,
    required this.tempMax,
    required this.humidityMin,
    required this.humidityMax,
    required this.motionMax,
    required this.soundMax,
    required this.updatedAt,
  });

  // Default comfort ranges shown as hints in the UI.
  // Based on general medical/environmental guidance.
  // Caregivers can override these for their individual's specific needs.
  factory ThresholdModel.defaults({
    required String userId,
    required String deviceId,
  }) {
    return ThresholdModel(
      userId:       userId,
      deviceId:     deviceId,
      tempMin:      18.0,
      tempMax:      26.0,
      humidityMin:  30.0,
      humidityMax:  60.0,
      motionMax:    2.0,
      soundMax:     40.0,
      updatedAt:    DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId':       userId,
      'deviceId':     deviceId,
      'tempMin':      tempMin,
      'tempMax':      tempMax,
      'humidityMin':  humidityMin,
      'humidityMax':  humidityMax,
      'motionMax':    motionMax,
      'soundMax':     soundMax,
      'updatedAt':    updatedAt.toIso8601String(),
    };
  }

  factory ThresholdModel.fromJson(Map<String, dynamic> json) {
    return ThresholdModel(
      userId:      json['userId']       ?? '',
      deviceId:    json['deviceId']     ?? '',
      tempMin:     (json['tempMin']     ?? 18.0).toDouble(),
      tempMax:     (json['tempMax']     ?? 26.0).toDouble(),
      humidityMin: (json['humidityMin'] ?? 30.0).toDouble(),
      humidityMax: (json['humidityMax'] ?? 60.0).toDouble(),
      motionMax:   (json['motionMax']   ?? 2.0).toDouble(),
      soundMax:    (json['soundMax']    ?? 40.0).toDouble(),
      updatedAt:   DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  bool tempInRange(double temp)         => temp >= tempMin && temp <= tempMax;
  bool humidityInRange(double humidity) => humidity >= humidityMin && humidity <= humidityMax;
  bool motionInRange(double motion)     => motion <= motionMax;
  bool soundInRange(double sound)       => sound <= soundMax;
}