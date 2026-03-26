import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/threshold_service.dart';
import '../../services/discomfort_service.dart';
import '../../services/notification_service.dart';
import '../../models/user_model.dart';
import '../../models/sensor_data_model.dart';
import '../../models/alert_model.dart';
import '../../models/threshold_model.dart';
import '../../utils/constants.dart';
import '../monitoring/monitoring_screen.dart';
import '../threshold/threshold_settings_screen.dart';
import '../device/device_assignment_screen.dart';
import '../../utils/navigation_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  UserModel?        _currentUser;
  SensorDataModel?  _currentSensorData;
  ThresholdModel?   _currentThresholds;
  AlertEvent?       _latestAlert;
  List<AlertEvent>  _alertHistory = [];
  List<ThresholdBreachDetail> _activeBreaches = [];

  // Stream subscriptions — stored so we can cancel in dispose()
  StreamSubscription<SensorDataModel?>? _sensorSubscription;
  StreamSubscription<ThresholdModel?>?  _thresholdSubscription;
  StreamSubscription<List<AlertEvent>>? _alertSubscription;
  bool _lastHardwareFallDetected = false;
  DateTime? _lastHardwareFallAlertAt;
  static const int _hardwareFallAlertCooldownSeconds = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _thresholdSubscription?.cancel();
    _alertSubscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user        = await authService.getCurrentUserModel();
      if (!mounted) return;
      setState(() => _currentUser = user);
      if (user != null) _setupStreams(user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user: $e')),
        );
      }
    }
  }

  void _setupStreams(UserModel user) {
    final firebaseService   = Provider.of<FirebaseService>(context, listen: false);
    final thresholdService  = Provider.of<ThresholdService>(context, listen: false);
    final discomfortService = Provider.of<DiscomfortService>(context, listen: false);
    final notifService      = Provider.of<NotificationService>(context, listen: false);

    final deviceId = user.assignedDeviceId ?? AppConstants.defaultDeviceId;

    // Fetch current data immediately
    firebaseService.fetchCurrentSensorData(deviceId).then((data) {
      if (mounted && data != null) setState(() => _currentSensorData = data);
    });

    firebaseService.fetchThresholds(
      userId: user.uid, deviceId: deviceId,
    ).then((t) {
      if (mounted) setState(() => _currentThresholds = t);
    });

    firebaseService.fetchAlertHistory(user.uid, limit: 20).then((history) {
      if (mounted) setState(() => _alertHistory = history);
    });

    // Real-time sensor stream
    _sensorSubscription = firebaseService
        .getCurrentSensorData(deviceId)
        .listen((data) async {
      if (data == null || !mounted) return;
      setState(() => _currentSensorData = data);

      // Hardware-driven fall reporting from Firebase:
      // trigger on false->true transitions, with cooldown as extra guard.
      final now = DateTime.now();
      final hardwareFallSignal =
          data.fallDetected || data.fallConfidence >= 0.8;
      final cooldownPassed = _lastHardwareFallAlertAt == null ||
          now.difference(_lastHardwareFallAlertAt!).inSeconds >=
              _hardwareFallAlertCooldownSeconds;
      final shouldTriggerFallAlert =
          hardwareFallSignal &&
          (!_lastHardwareFallDetected || cooldownPassed);

      if (data.fallDetected || data.fallConfidence > 0) {
        debugPrint(
            'Dashboard: fall signal incoming detected=${data.fallDetected} confidence=${data.fallConfidence.toStringAsFixed(2)}');
      }

      if (shouldTriggerFallAlert && mounted) {
        final confidence =
            data.fallConfidence > 0 ? data.fallConfidence.clamp(0.0, 1.0) : 0.9;
        final fallAlert = AlertEvent(
          type: AlertType.fall,
          confidence: confidence,
          message:
              'Hardware fall detected (${(confidence * 100).toStringAsFixed(0)}% confidence)',
          indicators: {
            'motion_magnitude': data.motion.magnitude,
            'sound': data.sound,
            'angle_x': data.motion.angleX,
            'angle_y': data.motion.angleY,
            'angle_z': data.motion.angleZ,
            'source': 'hardware',
          },
          detectedAt: now,
        );

        await firebaseService.saveAlertEvent(user.uid, fallAlert);
        await notifService.showFallAlert(fallAlert);
        _lastHardwareFallAlertAt = now;
        setState(() {
          _latestAlert = fallAlert;
          _alertHistory = [fallAlert, ..._alertHistory].take(50).toList();
        });
      }
      _lastHardwareFallDetected = hardwareFallSignal;

      // Threshold/discomfort checks depend on loaded thresholds.
      if (_currentThresholds == null) return;

      // Check threshold breaches per sensor
      final breaches = discomfortService.checkThresholdBreaches(
        data:       data,
        thresholds: _currentThresholds!,
      );

      // Notify each new breach
      for (final breach in breaches) {
        await notifService.showThresholdBreachAlert(breach);
      }

      // Run discomfort scoring
      final discomfortAlert = discomfortService.analyse(
        data:       data,
        thresholds: _currentThresholds!,
      );

      if (discomfortAlert != null) {
        await firebaseService.saveAlertEvent(user.uid, discomfortAlert);
        await notifService.showDiscomfortAlert(discomfortAlert);
      }

      final goodConditionAlert = discomfortService.evaluateGoodCondition(
        data: data,
        thresholds: _currentThresholds!,
      );
      if (goodConditionAlert != null) {
        await firebaseService.saveAlertEvent(user.uid, goodConditionAlert);
      }

      if (mounted) {
        setState(() {
          _activeBreaches = breaches;
          if (discomfortAlert != null) {
            _latestAlert = discomfortAlert;
            _alertHistory = [discomfortAlert, ..._alertHistory].take(50).toList();
          } else if (goodConditionAlert != null) {
            _latestAlert = goodConditionAlert;
            _alertHistory =
                [goodConditionAlert, ..._alertHistory].take(50).toList();
          }
        });
      }
    });

    // Threshold stream — updates if caregiver changes settings elsewhere
    _thresholdSubscription = thresholdService
        .watchThresholds(userId: user.uid, deviceId: deviceId)
        .cast<ThresholdModel?>()
        .listen((t) {
      if (mounted) setState(() => _currentThresholds = t);
    });

    // Alert history stream
    _alertSubscription = firebaseService
        .watchAlertHistory(user.uid, limit: 20)
        .listen((alerts) {
      if (mounted) setState(() => _alertHistory = alerts);
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      if (mounted) Navigator.of(context).pushReplacementNamed('/signin');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Monitor'),
        elevation: 0,
        actions: [
          IconButton(
            icon:    const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _init(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 16),
              if (_latestAlert != null && _latestAlert!.type == AlertType.fall) ...[
                _buildFallAlertCard(),
                const SizedBox(height: 16),
              ],
              if (_activeBreaches.isNotEmpty) ...[
                _buildBreachesCard(),
                const SizedBox(height: 16),
              ],
              if (_latestAlert != null && _latestAlert!.type == AlertType.discomfort) ...[
                _buildDiscomfortCard(),
                const SizedBox(height: 16),
              ],
              _currentSensorData != null
                  ? _buildSensorCard()
                  : _buildNoSensorCard(),
              const SizedBox(height: 16),
              _buildQuickActions(),
              const SizedBox(height: 16),
              if (_alertHistory.isNotEmpty) _buildAlertHistory(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────────

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:  Theme.of(context).colorScheme.primary,
                shape:  BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _currentUser != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${_currentUser!.name}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          _currentUser!.role,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallAlertCard() {
    final event      = _latestAlert!;
    final confidence = (event.confidence * 100).toInt();
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.red, width: 2),
      ),
      color: Colors.red.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.warning_rounded, color: Colors.red, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fall Detected',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        '$confidence% confidence',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Please check on the person immediately.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _acknowledgeFallAlert,
                icon: const Icon(Icons.check_circle),
                label: const Text('I checked on the person'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledgeFallAlert() async {
    final user = _currentUser;
    final current = _latestAlert;
    if (user == null || current == null || current.type != AlertType.fall) {
      return;
    }

    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    final acknowledged = AlertEvent(
      type: AlertType.normal,
      confidence: 1.0,
      message: 'Caregiver checked on the person after fall alert.',
      indicators: {
        'source': 'caregiver_acknowledgement',
        'related_alert_type': 'fall',
        'related_detected_at': current.detectedAt.toIso8601String(),
      },
      detectedAt: DateTime.now(),
    );

    await firebaseService.saveAlertEvent(user.uid, acknowledged);
    if (!mounted) return;

    setState(() {
      if (_latestAlert?.type == AlertType.fall) {
        _latestAlert = null;
      }
      _alertHistory = [acknowledged, ..._alertHistory].take(50).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Acknowledged. Glad you checked.')),
    );
  }

  Widget _buildBreachesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.orange.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: Colors.orange[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  'Threshold Breaches',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._activeBreaches.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.orange[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b.breachMessage,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscomfortCard() {
    final event      = _latestAlert!;
    final confidence = (event.confidence * 100).toInt();
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.amber.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.sick, color: Colors.amber, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Possible Discomfort ($confidence%)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.message,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard() {
    final d = _currentSensorData!;
    final t = _currentThresholds;

    Color tempColor  = t == null || t.tempInRange(d.temperature)
        ? Colors.red : Colors.orange;
    Color humColor   = t == null || t.humidityInRange(d.humidity)
        ? Colors.blue : Colors.orange;
    Color motColor   = t == null || t.motionInRange(d.motion.magnitude)
        ? Colors.purple : Colors.orange;
    Color sndColor   = t == null || t.soundInRange(d.sound.toDouble())
        ? Colors.green : Colors.orange;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors,
                    color: Theme.of(context).colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Current Readings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    '${d.temperature.toStringAsFixed(1)}°C',
                    'Temperature',
                    Icons.thermostat,
                    tempColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetric(
                    '${d.humidity.toStringAsFixed(1)}%',
                    'Humidity',
                    Icons.water_drop,
                    humColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    '${d.motion.magnitude.toStringAsFixed(2)} m/s²',
                    'Motion',
                    Icons.accessibility_new,
                    motColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetric(
                    '${d.sound} units',
                    'Sound',
                    Icons.volume_up,
                    sndColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoSensorCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.sensors_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Sensor Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your device to see readings',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                title: 'Monitoring',
                icon:  Icons.monitor_heart_outlined,
                color: Colors.green,
                onTap: () => NavigationHelper.pushFast(
                  context, const MonitoringScreen(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                title: 'Thresholds',
                icon:  Icons.tune,
                color: Colors.blue,
                onTap: () => NavigationHelper.pushFast(
                  context, const ThresholdSettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildActionCard(
          title:     'Device Assignment',
          icon:      Icons.devices_outlined,
          color:     Colors.purple,
          onTap:     () => NavigationHelper.pushFast(
            context, const DeviceAssignmentScreen(),
          ),
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required String   title,
    required IconData icon,
    required Color    color,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color.withOpacity(0.1),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: fullWidth
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:        color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey[400]),
                  ],
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:        color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign:  TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAlertHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Alerts',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 12),
        ..._alertHistory.take(10).map(_buildAlertHistoryItem),
      ],
    );
  }

  Widget _buildAlertHistoryItem(AlertEvent event) {
    Color color;
    IconData icon;
    switch (event.type) {
      case AlertType.fall:
        color = Colors.red;
        icon  = Icons.warning_rounded;
        break;
      case AlertType.discomfort:
        color = Colors.amber;
        icon  = Icons.sick;
        break;
      case AlertType.thresholdBreach:
        color = Colors.orange;
        icon  = Icons.sensors;
        break;
      case AlertType.normal:
        color = Colors.green;
        icon  = Icons.check_circle;
        break;
    }

    final time = event.detectedAt;
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          event.type.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          event.message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Text(
          timeStr,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ),
    );
  }
}