import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device_model.dart';
import '../utils/constants.dart';

/// Service for managing device registration and user-device associations
class DeviceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Register a new device in the system
  Future<void> registerDevice({
    required String deviceId,
    required String name,
    String? assignedUserId,
    String? patientId,
  }) async {
    try {
      final deviceMetadata = {
        'deviceId': deviceId,
        'name': name,
        'assignedUserId': assignedUserId,
        'patientId': patientId,
        'registeredAt': DateTime.now().toIso8601String(),
        'lastSeen': DateTime.now().toIso8601String(),
        'status': DeviceStatus.active.name,
        'hardwareInfo': {
          'model': 'MXChip AZ3166',
          'firmwareVersion': '1.0',
        },
      };

      // Store device metadata in Realtime Database
      await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('metadata')
          .set(deviceMetadata);

      // Also store in Firestore for easier querying (non-blocking)
      _firestore
          .collection('devices')
          .doc(deviceId)
          .set(deviceMetadata)
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
        debugPrint('Firestore device write failed (non-critical): $e');
      });
    } catch (e) {
      throw 'Error registering device: ${e.toString()}';
    }
  }

  // Assign device to a user
  Future<void> assignDeviceToUser({
    required String deviceId,
    required String userId,
    String? patientId,
  }) async {
    try {
      // Update device metadata
      await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('metadata')
          .update({
        'assignedUserId': userId,
        'patientId': patientId,
        'lastSeen': DateTime.now().toIso8601String(),
        'status': DeviceStatus.active.name,
      });

      // Update Firestore (non-blocking)
      _firestore
          .collection('devices')
          .doc(deviceId)
          .update({
        'assignedUserId': userId,
        'patientId': patientId,
        'lastSeen': DateTime.now().toIso8601String(),
        'status': DeviceStatus.active.name,
      }).timeout(const Duration(seconds: 2)).catchError((e) {
        debugPrint('Firestore device update failed (non-critical): $e');
      });

      _firestore
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({
        'assignedDeviceId': deviceId,
      }).timeout(const Duration(seconds: 2)).catchError((e) {
        debugPrint('Firestore user update failed (non-critical): $e');
      });
    } catch (e) {
      throw 'Error assigning device: ${e.toString()}';
    }
  }

  // Get device metadata - use Realtime DB only (Firestore is optional)
  Future<DeviceModel?> getDevice(String deviceId) async {
    try {
      // Use Realtime Database (primary) - Firestore is optional
      final snapshot = await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('metadata')
          .get()
          .timeout(const Duration(seconds: 3));

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        return DeviceModel.fromJson(data);
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching device from Realtime DB: $e');
      return null;
    }
  }

  // Get all available devices (not assigned) - use Realtime DB
  Stream<List<DeviceModel>> getAvailableDevices() {
    return _database
        .child(AppConstants.devicesCollection)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return <DeviceModel>[];
      try {
        final data = event.snapshot.value as Map;
        return data.entries
            .where((entry) {
              final metadata = entry.value['metadata'];
              return metadata != null && metadata['assignedUserId'] == null;
            })
            .map((entry) {
              final metadata = entry.value['metadata'] as Map;
              return DeviceModel.fromJson(Map<String, dynamic>.from(metadata));
            })
            .toList();
      } catch (e) {
        debugPrint('Error parsing devices: $e');
        return <DeviceModel>[];
      }
    });
  }

  // Get devices assigned to a user - use Realtime DB
  Stream<List<DeviceModel>> getUserDevices(String userId) {
    return _database
        .child(AppConstants.devicesCollection)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return <DeviceModel>[];
      try {
        final data = event.snapshot.value as Map;
        return data.entries
            .where((entry) {
              final metadata = entry.value['metadata'];
              return metadata != null && metadata['assignedUserId'] == userId;
            })
            .map((entry) {
              final metadata = entry.value['metadata'] as Map;
              return DeviceModel.fromJson(Map<String, dynamic>.from(metadata));
            })
            .toList();
      } catch (e) {
        debugPrint('Error parsing user devices: $e');
        return <DeviceModel>[];
      }
    });
  }

  // Get device assigned to user - use Realtime DB
  Future<DeviceModel?> getUserAssignedDevice(String userId) async {
    try {
      // Check Realtime Database for user's device assignment
      final userSnapshot = await _database
          .child('users')
          .child(userId)
          .child('assignedDeviceId')
          .get()
          .timeout(const Duration(seconds: 2));

      if (!userSnapshot.exists || userSnapshot.value == null) return null;

      final assignedDeviceId = userSnapshot.value.toString();
      return getDevice(assignedDeviceId);
    } catch (e) {
      debugPrint('Error fetching user device: $e');
      return null;
    }
  }

  // Update device last seen timestamp
  Future<void> updateDeviceLastSeen(String deviceId) async {
    try {
      final now = DateTime.now().toIso8601String();
      
      await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('metadata')
          .update({
        'lastSeen': now,
        'status': DeviceStatus.active.name,
      });

      // Firestore update (non-blocking)
      _firestore
          .collection('devices')
          .doc(deviceId)
          .update({
        'lastSeen': now,
        'status': DeviceStatus.active.name,
      }).timeout(const Duration(seconds: 1)).catchError((e) {
        // Silent fail
      });
    } catch (e) {
      // Silent fail for last seen updates
      debugPrint('Error updating device last seen: $e');
    }
  }

  // Check if device exists and is active
  Future<bool> isDeviceActive(String deviceId) async {
    try {
      final device = await getDevice(deviceId);
      if (device == null) return false;

      // Check if device has sent data recently (within last 5 minutes)
      if (device.lastSeen != null) {
        final timeSinceLastSeen = DateTime.now().difference(device.lastSeen!);
        return timeSinceLastSeen.inMinutes < 5;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}

