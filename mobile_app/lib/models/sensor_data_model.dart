class SensorDataModel {
  final String deviceId;
  final DateTime timestamp;
  final double temperature;
  final double humidity;
  final MotionData motion;
  final int sound;
  final bool fallDetected;
  final double fallConfidence;
  final DateTime receivedAt;

  SensorDataModel({
    required this.deviceId,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.motion,
    required this.sound,
    required this.fallDetected,
    required this.fallConfidence,
    required this.receivedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'temperature': temperature,
      'humidity': humidity,
      'sensors': {
        'motion': motion.toJson(),
        'sound': {'raw': sound},
      },
      'fall_detection': {
        'detected': fallDetected,
        'confidence': fallConfidence,
      },
      'received_at': receivedAt.toIso8601String(),
    };
  }

  factory SensorDataModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> safeConvertMap(dynamic value) {
      if (value == null) return <String, dynamic>{};
      if (value is Map) {
        return value.map((k, v) {
          if (v is Map) return MapEntry(k.toString(), safeConvertMap(v));
          return MapEntry(k.toString(), v);
        });
      }
      return <String, dynamic>{};
    }

    final safeJson     = safeConvertMap(json);
    final sensors      = safeConvertMap(safeJson['sensors']);
    final motionData   = safeConvertMap(sensors['motion']);
    final fallData     = safeConvertMap(safeJson['fall_detection']);

    bool parseBoolLike(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        return normalized == 'true' ||
            normalized == '1' ||
            normalized == 'yes';
      }
      return false;
    }

    double parseDoubleLike(dynamic value, {double fallback = 0.0}) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    // Timestamp — hardware sends seconds since boot, not unix epoch.
    // Correct threshold: anything under 10 billion is seconds, convert to ms.
    int timestampMs;
    final ts = safeJson['timestamp'];
    if (ts != null) {
      if (ts is int) {
        timestampMs = ts < 10000000000 ? ts * 1000 : ts;
      } else if (ts is num) {
        timestampMs = (ts < 10000000000 ? ts * 1000 : ts).toInt();
      } else {
        timestampMs = DateTime.now().millisecondsSinceEpoch;
      }
    } else {
      timestampMs = DateTime.now().millisecondsSinceEpoch;
    }

    DateTime receivedAt;
    final receivedAtStr = safeJson['received_at'];
    if (receivedAtStr != null) {
      try {
        receivedAt = DateTime.parse(receivedAtStr.toString());
      } catch (_) {
        receivedAt = DateTime.now();
      }
    } else {
      receivedAt = DateTime.now();
    }

    final temp     = sensors['temperature'] ?? safeJson['temperature'] ?? 0.0;
    final hum      = sensors['humidity']    ?? safeJson['humidity']    ?? 0.0;
    final soundVal = sensors['sound']?['raw'] ?? sensors['sound'] ?? safeJson['sound'] ?? 0;
    final soundInt = soundVal is int ? soundVal : (soundVal is num ? soundVal.toInt() : 0);

    // Fall detection fields:
    // support multiple payload styles (nested + flat, bool + int + string).
    final rawFallDetected =
        fallData['detected'] ?? safeJson['fall_detected'] ?? sensors['fall_detected'];
    final rawFallConfidence = fallData['confidence'] ??
        safeJson['fall_confidence'] ??
        sensors['fall_confidence'];
    final fallDetected = parseBoolLike(rawFallDetected);
    final fallConfidence = parseDoubleLike(rawFallConfidence).clamp(0.0, 1.0);

    return SensorDataModel(
      deviceId:       safeJson['device_id']?.toString() ?? '',
      timestamp:      DateTime.fromMillisecondsSinceEpoch(timestampMs),
      temperature:    (temp is num ? temp : double.tryParse(temp.toString()) ?? 0.0).toDouble(),
      humidity:       (hum  is num ? hum  : double.tryParse(hum.toString())  ?? 0.0).toDouble(),
      motion:         MotionData.fromJson(motionData),
      sound:          soundInt,
      fallDetected:   fallDetected,
      fallConfidence: fallConfidence,
      receivedAt:     receivedAt,
    );
  }
}

class MotionData {
  final double magnitude;
  final double x;
  final double y;
  final double z;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double magX;
  final double magY;
  final double magZ;
  final double angleX;
  final double angleY;
  final double angleZ;
  final double heading;

  MotionData({
    required this.magnitude,
    required this.x,
    required this.y,
    required this.z,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.magX,
    required this.magY,
    required this.magZ,
    required this.angleX,
    required this.angleY,
    required this.angleZ,
    required this.heading,
  });

  Map<String, dynamic> toJson() {
    return {
      'magnitude': magnitude,
      'x': x,
      'y': y,
      'z': z,
      'gyro_x': gyroX,
      'gyro_y': gyroY,
      'gyro_z': gyroZ,
      'mag_x': magX,
      'mag_y': magY,
      'mag_z': magZ,
      'angle_x': angleX,
      'angle_y': angleY,
      'angle_z': angleZ,
      'heading': heading,
    };
  }

  factory MotionData.fromJson(Map<String, dynamic> json) {
    final safe = json.map((k, v) => MapEntry(k.toString(), v));
    return MotionData(
      magnitude: ((safe['magnitude'] ?? 0.0) as num).toDouble(),
      x:         ((safe['x']         ?? 0.0) as num).toDouble(),
      y:         ((safe['y']         ?? 0.0) as num).toDouble(),
      z:         ((safe['z']         ?? 0.0) as num).toDouble(),
      gyroX:     ((safe['gyro_x']    ?? 0.0) as num).toDouble(),
      gyroY:     ((safe['gyro_y']    ?? 0.0) as num).toDouble(),
      gyroZ:     ((safe['gyro_z']    ?? 0.0) as num).toDouble(),
      magX:      ((safe['mag_x']     ?? 0.0) as num).toDouble(),
      magY:      ((safe['mag_y']     ?? 0.0) as num).toDouble(),
      magZ:      ((safe['mag_z']     ?? 0.0) as num).toDouble(),
      angleX:    ((safe['angle_x']   ?? 0.0) as num).toDouble(),
      angleY:    ((safe['angle_y']   ?? 0.0) as num).toDouble(),
      angleZ:    ((safe['angle_z']   ?? 0.0) as num).toDouble(),
      heading:   ((safe['heading']   ?? 0.0) as num).toDouble(),
    );
  }
}