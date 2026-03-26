import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data_model.dart';
import '../models/alert_model.dart';
import '../models/threshold_model.dart';

class FirebaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // ── Sensor Data ───────────────────────────────────────────────────────────

  Future<SensorDataModel?> fetchCurrentSensorData(String deviceId) async {
    try {
      final snapshot = await _database
          .child('devices')
          .child(deviceId)
          .child('current')
          .get();

      if (snapshot.value == null) return null;
      return _parseSensorData(snapshot.value);
    } catch (e) {
      debugPrint('FirebaseService: Error fetching sensor data: $e');
      return null;
    }
  }

  Stream<SensorDataModel?> getCurrentSensorData(String deviceId) {
    return _database
        .child('devices')
        .child(deviceId)
        .child('current')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return null;
      try {
        return _parseSensorData(event.snapshot.value);
      } catch (e) {
        debugPrint('FirebaseService: Error parsing sensor stream: $e');
        return null;
      }
    });
  }

  Future<List<SensorDataModel>> fetchHistoricalSensorData(
    String deviceId, {
    int limit = 100,
  }) async {
    try {
      final snapshot = await _database
          .child('devices')
          .child(deviceId)
          .child('history')
          .orderByKey()
          .limitToLast(limit)
          .get();

      if (snapshot.value == null) return [];

      final data = snapshot.value as Map;
      final result = data.entries
          .map((e) {
            try {
              return _parseSensorData(e.value);
            } catch (_) {
              return null;
            }
          })
          .whereType<SensorDataModel>()
          .toList();

      result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return result;
    } catch (e) {
      debugPrint('FirebaseService: Error fetching history: $e');
      return [];
    }
  }

  // ── Thresholds ────────────────────────────────────────────────────────────

  Future<ThresholdModel> fetchThresholds({
    required String userId,
    required String deviceId,
  }) async {
    try {
      final snapshot = await _database
          .child('thresholds')
          .child(userId)
          .child(deviceId)
          .get();

      if (snapshot.value == null) {
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }

      final raw  = snapshot.value as Map;
      final data = _convertMap(raw);
      return ThresholdModel.fromJson(data);
    } catch (e) {
      debugPrint('FirebaseService: Error fetching thresholds: $e');
      return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
    }
  }

  Future<void> saveThresholds(ThresholdModel model) async {
    try {
      await _database
          .child('thresholds')
          .child(model.userId)
          .child(model.deviceId)
          .set(model.toJson());
    } catch (e) {
      debugPrint('FirebaseService: Error saving thresholds: $e');
      rethrow;
    }
  }

  Stream<ThresholdModel> watchThresholds({
    required String userId,
    required String deviceId,
  }) {
    return _database
        .child('thresholds')
        .child(userId)
        .child(deviceId)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }
      try {
        final raw  = event.snapshot.value as Map;
        final data = _convertMap(raw);
        return ThresholdModel.fromJson(data);
      } catch (e) {
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }
    });
  }

  // ── Alert History ─────────────────────────────────────────────────────────

  Future<void> saveAlertEvent(String userId, AlertEvent event) async {
    try {
      final timestamp = event.detectedAt.millisecondsSinceEpoch;
      await _database
          .child('alerts')
          .child(userId)
          .child(timestamp.toString())
          .set(event.toJson());
    } catch (e) {
      debugPrint('FirebaseService: Error saving alert: $e');
    }
  }

  Future<List<AlertEvent>> fetchAlertHistory(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _database
          .child('alerts')
          .child(userId)
          .orderByKey()
          .limitToLast(limit)
          .get();

      if (snapshot.value == null) return [];

      final raw = snapshot.value as Map;
      final events = raw.entries
          .map((e) {
            try {
              final data = _convertMap(e.value as Map);
              return AlertEvent.fromJson(data);
            } catch (_) {
              return null;
            }
          })
          .whereType<AlertEvent>()
          .toList();

      events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
      return events;
    } catch (e) {
      debugPrint('FirebaseService: Error fetching alert history: $e');
      return [];
    }
  }

  Stream<List<AlertEvent>> watchAlertHistory(
    String userId, {
    int limit = 50,
  }) {
    return _database
        .child('alerts')
        .child(userId)
        .orderByKey()
        .limitToLast(limit)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return <AlertEvent>[];
      try {
        final raw = event.snapshot.value as Map;
        final events = raw.entries
            .map((e) {
              try {
                final data = _convertMap(e.value as Map);
                return AlertEvent.fromJson(data);
              } catch (_) {
                return null;
              }
            })
            .whereType<AlertEvent>()
            .toList();
        events.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
        return events;
      } catch (e) {
        return <AlertEvent>[];
      }
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  SensorDataModel? _parseSensorData(dynamic raw) {
    if (raw == null) return null;
    if (raw is! Map) return null;
    final data = _convertMap(raw);
    return SensorDataModel.fromJson(data);
  }

  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map) {
        result[stringKey] = _convertMap(Map<dynamic, dynamic>.from(value));
      } else if (value is List) {
        result[stringKey] = value.map((item) {
          if (item is Map) return _convertMap(Map<dynamic, dynamic>.from(item));
          return item;
        }).toList();
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }
}