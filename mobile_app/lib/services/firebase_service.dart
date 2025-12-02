import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/sensor_data_model.dart';
import '../models/emotional_state_model.dart';
import '../utils/constants.dart';

class FirebaseService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Fetch current sensor data immediately (one-time)
  Future<SensorDataModel?> fetchCurrentSensorData(String deviceId) async {
    try {
      final snapshot = await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('current')
          .get();
      
      if (snapshot.value == null) return null;
      
      try {
        final rawData = snapshot.value;
        Map<String, dynamic> data;
        
        if (rawData is Map) {
          data = rawData.map((key, value) {
            return MapEntry(key.toString(), value);
          });
          data = _convertMap(data);
        } else {
          return null;
        }
        
        return SensorDataModel.fromJson(data);
      } catch (e) {
        debugPrint('Error parsing sensor data: $e');
        return null;
      }
    } catch (e) {
      debugPrint('Error fetching current sensor data: $e');
      return null;
    }
  }

  // Get current sensor data stream
  Stream<SensorDataModel?> getCurrentSensorData(String deviceId) {
    return _database
        .child(AppConstants.devicesCollection)
        .child(deviceId)
        .child('current')
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return null;
      
      try {
        // Handle Firebase's Map<Object?, Object?> type
        final rawData = event.snapshot.value;
        Map<String, dynamic> data;
        
        if (rawData is Map) {
          data = rawData.map((key, value) {
            return MapEntry(key.toString(), value);
          });
          // Recursively convert nested maps
          data = _convertMap(data);
        } else {
          return null;
        }
        
        return SensorDataModel.fromJson(data);
      } catch (e) {
        debugPrint('Error parsing sensor data: $e');
        return null;
      }
    });
  }
  
  // Helper method to recursively convert Map<Object?, Object?> to Map<String, dynamic>
  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final stringKey = key.toString();
      if (value is Map) {
        result[stringKey] = _convertMap(Map<dynamic, dynamic>.from(value));
      } else if (value is List) {
        result[stringKey] = value.map((item) {
          if (item is Map) {
            return _convertMap(Map<dynamic, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        result[stringKey] = value;
      }
    });
    return result;
  }

  // Fetch historical sensor data once (one-time)
  Future<List<SensorDataModel>> fetchHistoricalSensorData(String deviceId, {int limit = 100}) async {
    try {
      final snapshot = await _database
          .child(AppConstants.devicesCollection)
          .child(deviceId)
          .child('history')
          .orderByKey()
          .limitToLast(limit)
          .get();
      
      if (snapshot.value == null) return [];

      try {
        final data = snapshot.value as Map;
        final result = data.entries
            .map((entry) {
              try {
                final entryData = entry.value;
                final convertedData = entryData is Map 
                    ? _convertMap(Map<dynamic, dynamic>.from(entryData))
                    : Map<String, dynamic>.from(entryData);
                return SensorDataModel.fromJson(convertedData);
              } catch (e) {
                debugPrint('Error parsing historical entry: $e');
                return null;
              }
            })
            .where((item) => item != null)
            .cast<SensorDataModel>()
            .toList();
        
        result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return result;
      } catch (e) {
        debugPrint('Error parsing historical data: $e');
        return [];
      }
    } catch (e) {
      debugPrint('Error fetching historical sensor data: $e');
      return [];
    }
  }

  // Get historical sensor data stream
  Stream<List<SensorDataModel>> getHistoricalSensorData(String deviceId, {int limit = 100}) {
    return _database
        .child(AppConstants.devicesCollection)
        .child(deviceId)
        .child('history')
        .orderByKey()
        .limitToLast(limit)
        .onValue
        .map((event) {
      if (event.snapshot.value == null) return [];

      try {
        final data = event.snapshot.value as Map;
        return data.entries
            .map((entry) => SensorDataModel.fromJson(Map<String, dynamic>.from(entry.value)))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      } catch (e) {
        debugPrint('Error parsing historical data: $e');
        return [];
      }
    });
  }

  // Save emotional state result
  Future<void> saveEmotionalState(String userId, EmotionalStateResult result) async {
    try {
      final currentPath = _database
          .child(AppConstants.emotionalStatesCollection)
          .child(userId)
          .child('current');
      
      final historyPath = _database
          .child(AppConstants.emotionalStatesCollection)
          .child(userId)
          .child('history')
          .child(result.detectedAt.millisecondsSinceEpoch.toString());

      // Save current state
      await currentPath.set(result.toJson());
      debugPrint('✅ Saved emotional state to: /${AppConstants.emotionalStatesCollection}/$userId/current');
      debugPrint('   State: ${result.state.name}, Confidence: ${result.confidence}');

      // Also save to history
      await historyPath.set(result.toJson());
      debugPrint('✅ Saved emotional state history to: /${AppConstants.emotionalStatesCollection}/$userId/history/${result.detectedAt.millisecondsSinceEpoch}');
    } catch (e) {
      debugPrint('❌ Error saving emotional state: $e');
      debugPrint('   Path: /${AppConstants.emotionalStatesCollection}/$userId/current');
      throw 'Error saving emotional state: ${e.toString()}';
    }
  }

  // Get current emotional state (one-time fetch)
  Future<EmotionalStateResult?> fetchCurrentEmotionalState(String userId) async {
    try {
      final path = '${AppConstants.emotionalStatesCollection}/$userId/current';
      debugPrint('🔍 FirebaseService: Fetching emotional state once from: /$path');
      
      final snapshot = await _database
          .child(AppConstants.emotionalStatesCollection)
          .child(userId)
          .child('current')
          .get();
      
      if (snapshot.value == null) {
        debugPrint('⚠️ FirebaseService: No emotional state data found at /$path');
        return null;
      }

      try {
        final rawData = snapshot.value as Map;
        debugPrint('   Raw data keys: ${rawData.keys.toList()}');
        
        final data = _convertMap(Map<dynamic, dynamic>.from(rawData));
        debugPrint('📊 Parsing emotional state from Firebase: ${data.toString()}');
        final result = EmotionalStateResult.fromJson(data);
        debugPrint('✅ FirebaseService: Successfully parsed emotional state: ${result.state.name}');
        return result;
      } catch (e, stackTrace) {
        debugPrint('❌ Error parsing emotional state: $e');
        debugPrint('   Stack trace: $stackTrace');
        debugPrint('   Raw data type: ${snapshot.value.runtimeType}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching emotional state: $e');
      debugPrint('   Stack trace: $stackTrace');
      return null;
    }
  }

  // Get current emotional state (stream)
  Stream<EmotionalStateResult?> getCurrentEmotionalState(String userId) {
    final path = '${AppConstants.emotionalStatesCollection}/$userId/current';
    debugPrint('🔍 FirebaseService: Listening to emotional state at: /$path');
    
    return _database
        .child(AppConstants.emotionalStatesCollection)
        .child(userId)
        .child('current')
        .onValue
        .map((event) {
      debugPrint('📥 FirebaseService: Received data from /$path');
      debugPrint('   Data exists: ${event.snapshot.value != null}');
      debugPrint('   Data type: ${event.snapshot.value?.runtimeType ?? 'null'}');
      
      if (event.snapshot.value == null) {
        debugPrint('⚠️ FirebaseService: No emotional state data found at /$path');
        return null;
      }

      try {
        final rawData = event.snapshot.value as Map;
        debugPrint('   Raw data keys: ${rawData.keys.toList()}');
        
        final data = _convertMap(Map<dynamic, dynamic>.from(rawData));
        debugPrint('   Converted data: $data');
        
        final result = EmotionalStateResult.fromJson(data);
        debugPrint('✅ FirebaseService: Successfully parsed emotional state');
        debugPrint('   State: ${result.state.name}, Confidence: ${result.confidence}');
        return result;
      } catch (e, stackTrace) {
        debugPrint('❌ FirebaseService: Error parsing emotional state: $e');
        debugPrint('   Stack trace: $stackTrace');
        debugPrint('   Raw data: ${event.snapshot.value}');
        return null;
      }
    });
  }

  // Fetch emotional state history (one-time fetch)
  Future<List<EmotionalStateResult>> fetchEmotionalStateHistory(String userId, {int limit = 50}) async {
    try {
      final path = '${AppConstants.emotionalStatesCollection}/$userId/history';
      debugPrint('🔍 FirebaseService: Fetching emotional state history once from: /$path (limit: $limit)');
      
      final snapshot = await _database
          .child(AppConstants.emotionalStatesCollection)
          .child(userId)
          .child('history')
          .orderByKey()
          .limitToLast(limit)
          .get();
      
      if (snapshot.value == null) {
        debugPrint('⚠️ FirebaseService: No history data found at /$path');
        return <EmotionalStateResult>[];
      }

      try {
        final rawData = snapshot.value as Map;
        debugPrint('   Raw history keys count: ${rawData.keys.length}');
        
        final convertedData = _convertMap(Map<dynamic, dynamic>.from(rawData));
        debugPrint('   Converted history entries: ${convertedData.keys.length}');
        
        final historyList = convertedData.entries
            .map((entry) {
              try {
                final entryValue = entry.value;
                final convertedEntry = entryValue is Map
                    ? _convertMap(Map<dynamic, dynamic>.from(entryValue))
                    : Map<String, dynamic>.from(entryValue);
                
                debugPrint('   Parsing history entry: ${entry.key}');
                final result = EmotionalStateResult.fromJson(convertedEntry);
                debugPrint('   ✅ Parsed: ${result.state.name} at ${result.detectedAt}');
                return result;
              } catch (e, stackTrace) {
                debugPrint('   ❌ Error parsing history entry ${entry.key}: $e');
                debugPrint('      Stack trace: $stackTrace');
                return null;
              }
            })
            .where((item) => item != null)
            .cast<EmotionalStateResult>()
            .toList()
          ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
        
        debugPrint('✅ FirebaseService: Successfully fetched ${historyList.length} history items');
        return historyList;
      } catch (e, stackTrace) {
        debugPrint('❌ Error parsing emotional state history: $e');
        debugPrint('   Stack trace: $stackTrace');
        debugPrint('   Raw data: ${snapshot.value}');
        return <EmotionalStateResult>[];
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching emotional state history: $e');
      debugPrint('   Stack trace: $stackTrace');
      return <EmotionalStateResult>[];
    }
  }

  // Get emotional state history (stream)
  Stream<List<EmotionalStateResult>> getEmotionalStateHistory(String userId, {int limit = 50}) {
    final path = '${AppConstants.emotionalStatesCollection}/$userId/history';
    debugPrint('🔍 FirebaseService: Listening to emotional state history at: /$path (limit: $limit)');
    
    return _database
        .child(AppConstants.emotionalStatesCollection)
        .child(userId)
        .child('history')
        .orderByKey()
        .limitToLast(limit)
        .onValue
        .map((event) {
      debugPrint('📥 FirebaseService: Received history data from /$path');
      debugPrint('   Data exists: ${event.snapshot.value != null}');
      debugPrint('   Data type: ${event.snapshot.value?.runtimeType ?? 'null'}');
      
      if (event.snapshot.value == null) {
        debugPrint('⚠️ FirebaseService: No history data found at /$path');
        return <EmotionalStateResult>[];
      }

      try {
        final rawData = event.snapshot.value as Map;
        debugPrint('   Raw history keys count: ${rawData.keys.length}');
        
        final convertedData = _convertMap(Map<dynamic, dynamic>.from(rawData));
        debugPrint('   Converted history entries: ${convertedData.keys.length}');
        
        final historyList = convertedData.entries
            .map((entry) {
              try {
                final entryValue = entry.value;
                final convertedEntry = entryValue is Map
                    ? _convertMap(Map<dynamic, dynamic>.from(entryValue))
                    : Map<String, dynamic>.from(entryValue);
                
                debugPrint('   Parsing history entry: ${entry.key}');
                final result = EmotionalStateResult.fromJson(convertedEntry);
                debugPrint('   ✅ Parsed: ${result.state.name} at ${result.detectedAt}');
                return result;
              } catch (e, stackTrace) {
                debugPrint('   ❌ Error parsing history entry ${entry.key}: $e');
                debugPrint('      Stack trace: $stackTrace');
                return null;
              }
            })
            .where((item) => item != null)
            .cast<EmotionalStateResult>()
            .toList()
          ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
        
        debugPrint('✅ FirebaseService: Successfully parsed ${historyList.length} history items');
        return historyList;
      } catch (e, stackTrace) {
        debugPrint('❌ Error parsing emotional state history: $e');
        debugPrint('   Stack trace: $stackTrace');
        debugPrint('   Raw data: ${event.snapshot.value}');
        return <EmotionalStateResult>[];
      }
    });
  }
}

