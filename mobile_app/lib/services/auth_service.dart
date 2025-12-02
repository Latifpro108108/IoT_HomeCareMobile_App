import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';
import 'device_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required String role, // 'caregiver' or 'patient'
    String? deviceId, // Optional device ID to assign during registration
  }) async {
    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = userCredential.user;
      if (user == null) return null;

      // Build user model synchronously
      final userModel = UserModel(
        uid: user.uid,
        email: user.email ?? email,
        name: name,
        role: role,
        assignedDeviceId: deviceId,
        createdAt: DateTime.now(),
      );

      // Kick off Firestore + device setup in the background so UI can move on immediately
      // Any errors here are logged but won't block the signup flow
      Future(() async {
        try {
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(user.uid)
              .set(userModel.toJson());

          // If device ID provided, register the device assignment
          if (deviceId != null && deviceId.isNotEmpty) {
            try {
              final deviceService = DeviceService();
              await deviceService.registerDevice(
                deviceId: deviceId,
                name: '$name\'s Device',
                assignedUserId: user.uid,
              );
              await deviceService.assignDeviceToUser(
                deviceId: deviceId,
                userId: user.uid,
              );
            } catch (e) {
              debugPrint('Warning: Could not register device during signup: $e');
            }
          }

          // Update Firebase Auth display name
          await user.updateDisplayName(name);
        } catch (e) {
          debugPrint('Warning: Error initializing user profile after signup: $e');
        }
      });

      // Return immediately so the UI can navigate without waiting for database writes
      return userModel;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      // Check for network-related errors
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') || 
          errorString.contains('timeout') || 
          errorString.contains('failed host lookup') ||
          errorString.contains('socketexception')) {
        throw 'Network error: Please check your internet connection and ensure Firebase Authentication is enabled in your Firebase Console.';
      }
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Sign in with email and password
  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = userCredential.user;
      if (user != null) {
        // Get user data from Firestore - with timeout and error handling
        try {
          final doc = await _firestore
              .collection(AppConstants.usersCollection)
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 3));

          if (doc.exists && doc.data() != null) {
            return UserModel.fromJson(doc.data()!);
          }
        } catch (e) {
          // Firestore failed - create user model from auth data only
          debugPrint('Firestore read failed, using auth data: $e');
          return UserModel(
            uid: user.uid,
            email: user.email ?? '',
            name: user.displayName ?? 'User',
            role: 'patient',
            createdAt: DateTime.now(),
          );
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      // Check for network-related errors
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('network') || 
          errorString.contains('timeout') || 
          errorString.contains('failed host lookup') ||
          errorString.contains('socketexception')) {
        throw 'Network error: Please check your internet connection and ensure Firebase Authentication is enabled in your Firebase Console.';
      }
      throw 'An unexpected error occurred: ${e.toString()}';
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw 'Error signing out: ${e.toString()}';
    }
  }

  // Get current user model - non-blocking with fallback
  Future<UserModel?> getCurrentUserModel() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final doc = await _firestore
          .collection(AppConstants.usersCollection)
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 2));

      if (doc.exists && doc.data() != null) {
        return UserModel.fromJson(doc.data()!);
      }
      
      // No Firestore data - return basic model from auth
      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? 'User',
        role: 'patient',
        createdAt: DateTime.now(),
      );
    } catch (e) {
      // Firestore failed - return basic model, don't throw
      debugPrint('Firestore unavailable, using auth data: $e');
      return UserModel(
        uid: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? 'User',
        role: 'patient',
        createdAt: DateTime.now(),
      );
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is invalid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      default:
        return 'Authentication failed: ${e.message}';
    }
  }
}

