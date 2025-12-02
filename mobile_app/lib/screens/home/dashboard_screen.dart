import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/baseline_service.dart';
import '../../services/notification_service.dart';
import '../../services/fall_detection_service.dart';
import '../../services/feeling_good_service.dart';
import '../../models/user_model.dart';
import '../../models/sensor_data_model.dart';
import '../../models/emotional_state_model.dart';
import '../../utils/constants.dart';
import '../baseline/baseline_recording_enhanced_screen.dart';
import '../monitoring/monitoring_screen.dart';
import '../device/device_assignment_screen.dart';
import '../../utils/navigation_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  UserModel? _currentUser;
  SensorDataModel? _currentSensorData;
  EmotionalStateResult? _currentEmotionalState;

  @override
  void initState() {
    super.initState();
    // Show UI immediately, load data asynchronously
    _loadUserDataAsync();
  }

  Future<void> _loadUserDataAsync() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.getCurrentUserModel();
      
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
        // Setup monitoring after user is loaded
        _setupRealtimeMonitoring();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading user data: $e')),
        );
      }
    }
  }

  void _setupRealtimeMonitoring() {
    if (_currentUser == null) {
      debugPrint('⚠️ Dashboard: Cannot setup monitoring - user is null');
      return;
    }
    
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    final baselineService = Provider.of<BaselineService>(context, listen: false);
    final notificationService = Provider.of<NotificationService>(context, listen: false);
    final fallDetectionService = Provider.of<FallDetectionService>(context, listen: false);
    final feelingGoodService = Provider.of<FeelingGoodService>(context, listen: false);

    // Get user's assigned device ID or use default
    final deviceId = _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;

    // Fetch current data immediately (don't wait for streams)
    Future.microtask(() async {
      // Fetch current sensor data immediately
      final currentSensorData = await firebaseService.fetchCurrentSensorData(deviceId);
      if (mounted && currentSensorData != null) {
        setState(() => _currentSensorData = currentSensorData);
      }
      
      // Fetch current emotional state immediately
      final currentState = await firebaseService.fetchCurrentEmotionalState(_currentUser!.uid);
      if (mounted) {
        setState(() => _currentEmotionalState = currentState);
      }
    });

    SensorDataModel? previousSensorData;
    DateTime? _lastEmotionalStateProcessTime;
    const _emotionalStateProcessInterval = Duration(seconds: 5); // Process every 5 seconds max

    // Listen to sensor data from user's assigned device
    firebaseService.getCurrentSensorData(deviceId).listen((sensorData) {
      if (sensorData != null && _currentUser != null) {
        if (mounted) {
          setState(() => _currentSensorData = sensorData);
        }

        // Run fall detection analysis (lightweight, can run frequently)
        fallDetectionService.analyzeSensorDataForFall(
          userId: _currentUser!.uid,
          deviceId: deviceId,
          currentData: sensorData,
          previousData: previousSensorData,
        ).then((event) {
          if (event != null) {
            // Fall detected - notification already shown by service
          }
        });

        // Update previous sensor data
        previousSensorData = sensorData;

        // Throttle emotional state processing (heavy operation)
        final now = DateTime.now();
        if (_lastEmotionalStateProcessTime == null || 
            now.difference(_lastEmotionalStateProcessTime!) >= _emotionalStateProcessInterval) {
          _lastEmotionalStateProcessTime = now;
          
          // Process emotional state for each condition that requires baseline (debounced)
          Future.microtask(() async {
        for (final condition in AppConstants.conditionsRequiringBaseline) {
              try {
                final hasBaseline = await baselineService.hasBaseline(
            userId: _currentUser!.uid,
            deviceId: deviceId,
            condition: condition,
                );
                
            if (hasBaseline && mounted) {
              final baseline = await baselineService.getBaseline(
                userId: _currentUser!.uid,
                deviceId: deviceId,
                condition: condition,
              );

                  if (baseline != null && mounted && _currentSensorData != null) {
                final result = baselineService.analyzeEmotionalState(
                      currentData: _currentSensorData!,
                  baseline: baseline,
                  targetCondition: condition,
                );

                // Save emotional state to Firebase
                try {
                  await firebaseService.saveEmotionalState(_currentUser!.uid, result);
                } catch (e) {
                  debugPrint('❌ Failed to save emotional state: $e');
                }

                // Show notification if state changed
                if (result.state != EmotionalState.normal && result.confidence >= AppConstants.defaultConfidenceThreshold) {
                  await notificationService.showEmotionalStateNotification(result);
                }

                if (mounted) {
                  setState(() => _currentEmotionalState = result);
                }
                  }
                }
              } catch (e) {
                debugPrint('❌ Error processing emotional state for $condition: $e');
              }
            }
          });
        }

        // Run feeling good detection (lightweight)
        feelingGoodService.detectFeelingGood(
          userId: _currentUser!.uid,
          deviceId: deviceId,
          currentData: sensorData,
          normalBaseline: null,
        );
      }
    });
    
    // Listen to emotional state directly from Firebase (for updates from other sources)
    firebaseService.getCurrentEmotionalState(_currentUser!.uid).listen(
      (state) {
        if (mounted && state != null) {
          setState(() => _currentEmotionalState = state);
        }
      },
      onError: (error) {
        debugPrint('❌ Dashboard: Error listening to emotional state stream: $error');
      },
      cancelOnError: false,
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/signin');
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mental Health Monitor'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_currentUser != null) {
            final firebaseService = Provider.of<FirebaseService>(context, listen: false);
            final state = await firebaseService.fetchCurrentEmotionalState(_currentUser!.uid);
            if (mounted) {
              setState(() => _currentEmotionalState = state);
            }
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Card
              _buildWelcomeCard(),
              const SizedBox(height: 20),
              
              // Current Emotional State - Large, Visual Card
              if (_currentEmotionalState != null)
                _buildModernEmotionalStateCard()
              else
                _buildNoEmotionalStateCard(),
              
              const SizedBox(height: 20),
              
              // Sensor Data - Compact Grid
              if (_currentSensorData != null)
                _buildModernSensorDataCard()
              else
                _buildNoSensorDataCard(),
              
              const SizedBox(height: 24),
              
              // Quick Actions - Grid Layout
              _buildQuickActionsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    if (_currentUser != null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${_currentUser!.name}!',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentUser!.role,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                'Loading user data...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildModernEmotionalStateCard() {
    final state = _currentEmotionalState!.state;
    final confidence = _currentEmotionalState!.confidence;
    
    Color cardColor;
    IconData icon;
    String statusText;
    
    switch (state) {
      case EmotionalState.anxiety:
        cardColor = Colors.orange;
        icon = Icons.mood_bad;
        statusText = 'Anxiety Detected';
        break;
      case EmotionalState.stress:
        cardColor = Colors.red;
        icon = Icons.warning;
        statusText = 'Stress Detected';
        break;
      case EmotionalState.discomfort:
        cardColor = Colors.amber;
        icon = Icons.sick;
        statusText = 'Discomfort Detected';
        break;
      case EmotionalState.normal:
        cardColor = Colors.green;
        icon = Icons.check_circle;
        statusText = 'Normal State';
        break;
      case EmotionalState.unknown:
        cardColor = Colors.grey;
        icon = Icons.help;
        statusText = 'Unknown State';
        break;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: cardColor.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Icon and Status
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: cardColor),
            ),
            const SizedBox(height: 16),
            Text(
              statusText,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cardColor,
                  ),
            ),
            const SizedBox(height: 8),
            // Confidence Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${(confidence * 100).toInt()}% Confidence',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(cardColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoEmotionalStateCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.psychology_outlined, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Data Yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Record baselines to start monitoring',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSensorDataCard() {
    final data = _currentSensorData!;
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: Theme.of(context).colorScheme.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Current Sensor Data',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // 2x2 Grid of sensor values
            Row(
              children: [
                Expanded(child: _buildSensorMetric('Temperature', '${data.temperature.toStringAsFixed(1)}°C', Icons.thermostat, Colors.red)),
                const SizedBox(width: 12),
                Expanded(child: _buildSensorMetric('Humidity', '${data.humidity.toStringAsFixed(1)}%', Icons.water_drop, Colors.blue)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildSensorMetric('Motion', data.motion.magnitude.toStringAsFixed(2), Icons.accessibility_new, Colors.purple)),
                const SizedBox(width: 12),
                Expanded(child: _buildSensorMetric('Sound', '${data.sound}', Icons.volume_up, Colors.green)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorMetric(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoSensorDataCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.sensors_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Sensor Data',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your device to see readings',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildModernActionCard(
                title: 'Record\nBaselines',
                icon: Icons.assignment_outlined,
                color: Colors.blue,
                onTap: () {
                  NavigationHelper.pushFast(
                    context,
                    const BaselineRecordingEnhancedScreen(),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModernActionCard(
                title: 'Monitoring',
                icon: Icons.monitor_heart_outlined,
                color: Colors.green,
                onTap: () {
                  NavigationHelper.pushFast(
                    context,
                    const MonitoringScreen(),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildModernActionCard(
          title: 'Device Assignment',
          icon: Icons.devices_outlined,
          color: Colors.purple,
          onTap: () {
            NavigationHelper.pushFast(
              context,
              const DeviceAssignmentScreen(),
            );
          },
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildModernActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color.withOpacity(0.1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: fullWidth
              ? Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
