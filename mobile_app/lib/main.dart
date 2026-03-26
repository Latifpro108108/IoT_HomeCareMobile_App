import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'services/auth_service.dart';
import 'services/firebase_service.dart';
import 'services/threshold_service.dart';
import 'services/discomfort_service.dart';
import 'services/fall_detection_service.dart';
import 'services/notification_service.dart';
import 'services/device_service.dart';
import 'services/event_service.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/sign_up_screen.dart';
import 'screens/home/dashboard_screen.dart';
import 'screens/setup/firebase_setup_screen.dart';
import 'utils/app_theme.dart';
import 'firebase_options.dart';

bool _firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    try {
      Firebase.app();
      _firebaseInitialized = true;
    } catch (_) {
      final options = DefaultFirebaseOptions.currentPlatform;
      if (options.apiKey.contains('YOUR_') ||
          options.projectId.contains('YOUR_')) {
        _firebaseInitialized = false;
      } else {
        await Firebase.initializeApp(options: options);
        _firebaseInitialized = true;
      }
    }
  } catch (e) {
    _firebaseInitialized = false;
    debugPrint('Firebase initialization failed: $e');
  }

  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    debugPrint('Notification init error: $e');
  }

  runApp(MyApp(isFirebaseInitialized: _firebaseInitialized));
}

class MyApp extends StatelessWidget {
  final bool isFirebaseInitialized;
  const MyApp({super.key, required this.isFirebaseInitialized});

  @override
  Widget build(BuildContext context) {
    final List<SingleChildWidget> providers = [
      Provider<NotificationService>(create: (_) => NotificationService()),
    ];

    if (isFirebaseInitialized) {
      providers.addAll([
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<FirebaseService>(create: (_) => FirebaseService()),
        Provider<ThresholdService>(create: (_) => ThresholdService()),
        Provider<DiscomfortService>(create: (_) => DiscomfortService()),
        Provider<DeviceService>(create: (_) => DeviceService()),
        Provider<EventService>(create: (_) => EventService()),
        Provider<FallDetectionService>(
          create: (ctx) => FallDetectionService(
            Provider.of<EventService>(ctx, listen: false),
            Provider.of<NotificationService>(ctx, listen: false),
          ),
        ),
      ]);
    }

    return MultiProvider(
      providers: providers,
      child: MaterialApp(
        title: 'Wearable Health Monitor',
        theme:     AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
        home: isFirebaseInitialized
            ? const AuthWrapper()
            : const FirebaseSetupScreen(),
        routes: {
          '/signin': (context) => const SignInScreen(),
          '/signup': (context) => const SignUpScreen(),
          '/home':   (context) => const DashboardScreen(),
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return const DashboardScreen();
        }
        return const SignInScreen();
      },
    );
  }
}