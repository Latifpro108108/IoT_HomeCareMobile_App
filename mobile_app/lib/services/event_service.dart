import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/event_model.dart';

class EventService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Save event to Firestore - non-blocking
  Future<void> saveEvent(EventModel event) async {
    try {
      await _firestore
          .collection('events')
          .doc(event.id)
          .set(event.toJson())
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Event save failed (non-critical): $e');
      // Don't throw - allow app to continue
    }
  }

  // Get events for a user - with error handling
  Stream<List<EventModel>> getEvents(String userId, {int limit = 50}) {
    return _firestore
        .collection('events')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => EventModel.fromFirestore(doc))
            .toList())
        .handleError((error) {
      debugPrint('Error getting events: $error');
      return <EventModel>[];
    });
  }

  Future<List<EventModel>> fetchFallEventsForDevice(
    String deviceId, {
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('events')
          .where('deviceId', isEqualTo: deviceId)
          .where('type', isEqualTo: EventType.fall.name)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map(EventModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('Error fetching fall history: $e');
      return <EventModel>[];
    }
  }

  // Delete an event - non-blocking
  Future<void> deleteEvent(String eventId) async {
    try {
      await _firestore
          .collection('events')
          .doc(eventId)
          .delete()
          .timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Event delete failed (non-critical): $e');
      // Don't throw
    }
  }

  // Create event ID
  String generateEventId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

