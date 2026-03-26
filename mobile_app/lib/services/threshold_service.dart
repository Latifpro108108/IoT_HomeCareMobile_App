import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/threshold_model.dart';

class ThresholdService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  static const String _collection = 'thresholds';

  // Save or update thresholds for a user/device pair
  Future<void> saveThresholds(ThresholdModel model) async {
    try {
      await _database
          .child(_collection)
          .child(model.userId)
          .child(model.deviceId)
          .set(model.toJson());
      debugPrint('ThresholdService: Saved thresholds for ${model.userId}/${model.deviceId}');
    } catch (e) {
      debugPrint('ThresholdService: Error saving thresholds: $e');
      rethrow;
    }
  }

  // Fetch thresholds once — returns defaults if none saved yet
  Future<ThresholdModel> getThresholds({
    required String userId,
    required String deviceId,
  }) async {
    try {
      final snapshot = await _database
          .child(_collection)
          .child(userId)
          .child(deviceId)
          .get();

      if (snapshot.value == null) {
        debugPrint('ThresholdService: No thresholds found — returning defaults');
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }

      final raw = snapshot.value as Map;
      final data = raw.map((k, v) => MapEntry(k.toString(), v));
      return ThresholdModel.fromJson(data);
    } catch (e) {
      debugPrint('ThresholdService: Error fetching thresholds: $e');
      return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
    }
  }

  // Stream — updates in real time if caregiver changes thresholds from another device
  Stream<ThresholdModel> watchThresholds({
    required String userId,
    required String deviceId,
  }) {
    return _database
        .child(_collection)
        .child(userId)
        .child(deviceId)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) {
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }
      try {
        final raw  = event.snapshot.value as Map;
        final data = raw.map((k, v) => MapEntry(k.toString(), v));
        return ThresholdModel.fromJson(data);
      } catch (e) {
        debugPrint('ThresholdService: Error parsing threshold stream: $e');
        return ThresholdModel.defaults(userId: userId, deviceId: deviceId);
      }
    });
  }

  // Check if thresholds have been set (i.e. caregiver has configured them)
  Future<bool> hasThresholds({
    required String userId,
    required String deviceId,
  }) async {
    try {
      final snapshot = await _database
          .child(_collection)
          .child(userId)
          .child(deviceId)
          .get();
      return snapshot.value != null;
    } catch (e) {
      return false;
    }
  }
}