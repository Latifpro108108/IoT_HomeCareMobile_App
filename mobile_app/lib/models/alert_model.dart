// alert_model.dart
//
// Replaces EmotionalStateModel entirely.
// Anxiety and stress removed. System now focuses on:
//   - discomfort: inferred from weighted sensor score
//   - fall:       detected by hardware state machine, confirmed by Flutter
//   - threshold breach: single sensor crossed caregiver-defined range

enum AlertType {
  normal,
  discomfort,
  fall,
  thresholdBreach,
}

extension AlertTypeExtension on AlertType {
  String get displayName {
    switch (this) {
      case AlertType.normal:
        return 'Normal';
      case AlertType.discomfort:
        return 'Discomfort Detected';
      case AlertType.fall:
        return 'Fall Detected';
      case AlertType.thresholdBreach:
        return 'Threshold Breach';
    }
  }

  String get description {
    switch (this) {
      case AlertType.normal:
        return 'All readings are within the comfort range';
      case AlertType.discomfort:
        return 'Multiple sensor readings suggest the person may be uncomfortable';
      case AlertType.fall:
        return 'A fall event has been detected by the wearable device';
      case AlertType.thresholdBreach:
        return 'One or more sensor readings have left the defined comfort range';
    }
  }
}

// A single alert event — stored in Firebase and shown in the app
class AlertEvent {
  final AlertType type;
  final double confidence;       // 0.0 – 1.0
  final String message;          // Human-readable description for the caregiver
  final Map<String, dynamic> indicators; // Which sensors triggered this
  final DateTime detectedAt;

  AlertEvent({
    required this.type,
    required this.confidence,
    required this.message,
    required this.indicators,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'type':        type.name,
      'confidence':  confidence,
      'message':     message,
      'indicators':  indicators,
      'detectedAt':  detectedAt.toIso8601String(),
    };
  }

  factory AlertEvent.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? 'normal';
    final type = AlertType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => AlertType.normal,
    );

    return AlertEvent(
      type:       type,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      message:    json['message']?.toString() ?? '',
      indicators: json['indicators'] is Map
          ? Map<String, dynamic>.from(json['indicators'])
          : {},
      detectedAt: DateTime.tryParse(json['detectedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

// Threshold breach detail — one per sensor that is out of range
class ThresholdBreachDetail {
  final String sensorName;   // e.g. 'Temperature'
  final double currentValue;
  final double minValue;
  final double maxValue;
  final String unit;

  ThresholdBreachDetail({
    required this.sensorName,
    required this.currentValue,
    required this.minValue,
    required this.maxValue,
    required this.unit,
  });

  bool get isAboveMax => currentValue > maxValue;
  bool get isBelowMin => currentValue < minValue;

  String get breachMessage {
    if (isAboveMax) {
      return '$sensorName is too high: ${currentValue.toStringAsFixed(1)}$unit (max: ${maxValue.toStringAsFixed(1)}$unit)';
    } else {
      return '$sensorName is too low: ${currentValue.toStringAsFixed(1)}$unit (min: ${minValue.toStringAsFixed(1)}$unit)';
    }
  }
}