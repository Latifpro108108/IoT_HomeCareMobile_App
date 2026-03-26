import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/threshold_service.dart';
import '../services/discomfort_service.dart';
import '../services/fall_detection_service.dart';
import '../services/notification_service.dart';
import '../services/device_service.dart';
import '../services/event_service.dart';

class AppProviders {
  static List<SingleChildWidget> getProviders() {
    return [
      Provider<NotificationService>(create: (_) => NotificationService()),
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
    ];
  }
}
