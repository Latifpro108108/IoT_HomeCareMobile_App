# Troubleshooting Guide: Network Errors and Authentication Issues

## Important: No Local Server Required! 🚀

**The Flutter mobile app does NOT need a local server to run.** It connects directly to Firebase's cloud servers. The `backend/server.js` is only for the MXChip device to send sensor data - it's not needed for sign-in/sign-up.

## Common Network Timeout Issues

### 1. Firebase Authentication Not Enabled

**Problem:** Network timeouts when trying to sign in or sign up.

**Solution:**
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `mental-healthmonitor`
3. Navigate to **Authentication** → **Sign-in method**
4. Enable **Email/Password** authentication provider
5. Click **Save**

### 2. Internet Connection Issues

**Check:**
- Ensure your device/emulator has internet access
- Try accessing `https://identitytoolkit.googleapis.com` in a browser
- Check firewall settings if on a corporate network

### 3. Firebase Project Configuration

**Verify:**
- Your `firebase_options.dart` has correct API keys
- Your Firebase project ID matches: `mental-healthmonitor`
- The app is properly initialized (check console logs)

### 4. Android Emulator Network Issues

If using Android Emulator:
- Ensure emulator has internet access
- Try restarting the emulator
- Check that DNS is working: `adb shell ping 8.8.8.8`

### 5. iOS Simulator Network Issues

If using iOS Simulator:
- Ensure Mac has internet connection
- Check System Preferences → Network settings
- Try resetting network settings: `sudo killall -HUP mDNSResponder`

## Testing Firebase Connection

Run this in your Flutter app to test Firebase:

```dart
import 'package:firebase_auth/firebase_auth.dart';

// Test Firebase Auth connection
try {
  await FirebaseAuth.instance.signInAnonymously();
  print('✅ Firebase Auth is working!');
} catch (e) {
  print('❌ Firebase Auth error: $e');
}
```

## What Each Server Does

- **Flutter Mobile App**: Connects directly to Firebase (no local server needed)
- **Backend Server (`backend/server.js`)**: Only needed for MXChip device to send sensor data
- **Firebase Cloud**: Handles authentication, database, and storage

## Still Having Issues?

1. Check Flutter console logs for detailed error messages
2. Verify Firebase project is active and billing is enabled (if required)
3. Check Firebase Console → Authentication → Users to see if sign-ups are being blocked
4. Review Firebase Console → Project Settings → General for API restrictions

