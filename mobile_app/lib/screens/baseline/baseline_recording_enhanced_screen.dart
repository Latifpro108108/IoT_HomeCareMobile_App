import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/baseline_service.dart';
import '../../services/baseline_recording_service.dart';
import '../../services/firebase_service.dart';
import '../../models/user_model.dart';
import '../../models/sensor_data_model.dart';
import '../../models/baseline_model.dart';
import '../../utils/constants.dart';
import 'package:intl/intl.dart';

/// Enhanced baseline recording screen with better visuals and functionality
class BaselineRecordingEnhancedScreen extends StatefulWidget {
  const BaselineRecordingEnhancedScreen({super.key});

  @override
  State<BaselineRecordingEnhancedScreen> createState() => _BaselineRecordingEnhancedScreenState();
}

class _BaselineRecordingEnhancedScreenState extends State<BaselineRecordingEnhancedScreen> {
  UserModel? _currentUser;
  SensorDataModel? _currentSensorData;
  final Map<String, BaselineModel?> _baselines = {};
  final Map<String, bool> _isRecording = {}; // Track recording per condition
  final Map<String, Duration> _recordingRemaining = {}; // Track remaining time per condition
  final Map<String, int> _recordingCount = {}; // Track readings collected per condition
  bool _isLoading = true;
  final int _defaultDurationSeconds = AppConstants.defaultBaselineRecordingDurationSeconds;
  
  @override
  void initState() {
    super.initState();
    // Defer heavy loading until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserData();
    });
  }
  
  @override
  void dispose() {
    // Stop all recordings when leaving screen
    try {
      final recordingService = Provider.of<BaselineRecordingService>(context, listen: false);
      recordingService.stopAllRecordings();
    } catch (_) {
      // Service might not be available, ignore
    }
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.getCurrentUserModel();
      
      if (mounted) {
        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
        
        // Fetch current sensor data immediately
        if (user != null) {
          final firebaseService = Provider.of<FirebaseService>(context, listen: false);
          final deviceId = user.assignedDeviceId ?? AppConstants.defaultDeviceId;
          firebaseService.fetchCurrentSensorData(deviceId).then((data) {
            if (mounted && data != null) {
              setState(() => _currentSensorData = data);
            }
          });
        }
        
        // Load baselines and setup sensor listener asynchronously (don't block UI)
        Future.microtask(() {
          _loadBaselines();
          _setupSensorListener();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBaselines() async {
    if (_currentUser == null) return;

    final baselineService = Provider.of<BaselineService>(context, listen: false);
    final deviceId = _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;
    
    for (final condition in AppConstants.baselineConditions) {
      final baseline = await baselineService.getBaseline(
        userId: _currentUser!.uid,
        deviceId: deviceId,
        condition: condition,
      );
      
      if (mounted) {
        setState(() {
          _baselines[condition] = baseline;
        });
      }
    }
  }

  void _setupSensorListener() {
    if (_currentUser == null) return;
    
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    
    // Get user's assigned device ID or use default
    final deviceId = _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;
    
    firebaseService.getCurrentSensorData(deviceId).listen((sensorData) {
      if (mounted && sensorData != null) {
        setState(() => _currentSensorData = sensorData);
      }
    });
  }

  Future<void> _recordBaseline(String condition) async {
    if (_currentUser == null) {
      _showError('User not loaded. Please wait...');
      return;
    }

    final deviceId = _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;
    final recordingService = Provider.of<BaselineRecordingService>(context, listen: false);

    // Check if already recording this condition
    if (recordingService.isRecording(condition)) {
      // Stop recording
      await recordingService.stopRecording(condition);
      if (mounted) {
        setState(() {
          _isRecording.remove(condition);
          _recordingRemaining.remove(condition);
          _recordingCount.remove(condition);
        });
      }
      return;
    }

    // Start recording with duration
    if (mounted) {
      setState(() {
        _isRecording[condition] = true;
        _recordingRemaining[condition] = Duration(seconds: _defaultDurationSeconds);
        _recordingCount[condition] = 0;
      });
    }

    await recordingService.startRecording(
      userId: _currentUser!.uid,
      deviceId: deviceId,
      condition: condition,
      durationSeconds: _defaultDurationSeconds,
      onProgress: (cond, remaining) {
        if (mounted) {
          setState(() {
            _recordingRemaining[cond] = remaining;
            _recordingCount[cond] = recordingService.getRecordingCount(cond);
          });
        }
      },
      onComplete: (cond) {
        if (mounted) {
          setState(() {
            _isRecording.remove(cond);
            _recordingRemaining.remove(cond);
            _recordingCount.remove(cond);
          });
          _loadBaselines();
          _showSuccess('Baseline recorded successfully for ${cond.toUpperCase()}!');
        }
      },
      onError: (cond, error) {
        if (mounted) {
          setState(() {
            _isRecording.remove(cond);
            _recordingRemaining.remove(cond);
            _recordingCount.remove(cond);
          });
          _showError('Error recording baseline for $cond: $error');
        }
      },
    );
  }


  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildRecordingButton(String condition, Color cardColor, bool hasBaseline) {
    final isRecording = _isRecording[condition] ?? false;
    final remaining = _recordingRemaining[condition];
    final count = _recordingCount[condition] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _currentSensorData == null
                ? null
                : () => _recordBaseline(condition),
            icon: Icon(
              isRecording
                  ? Icons.stop
                  : (hasBaseline ? Icons.refresh : Icons.fiber_manual_record),
            ),
            label: Text(
              isRecording
                  ? 'Stop Recording'
                  : (hasBaseline ? 'Update Baseline (${_defaultDurationSeconds}s)' : 'Record Baseline (${_defaultDurationSeconds}s)'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : cardColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (isRecording && remaining != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (_defaultDurationSeconds - remaining.inSeconds) / _defaultDurationSeconds,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(cardColor),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${remaining.inSeconds}s',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cardColor,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Readings collected: $count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Baselines'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Info Card
            _buildInfoCard(),
            const SizedBox(height: 24),
            // Live Sensor Data Card
            if (_currentSensorData != null) ...[
              _buildLiveSensorCard(),
              const SizedBox(height: 24),
            ] else
              _buildNoDataCard(),
            const SizedBox(height: 24),
            // Baseline Conditions
            Text(
              'Baseline Conditions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Record baseline values for each condition when the person is calm and normal',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 16),
            ...AppConstants.baselineConditions.map((condition) => 
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildEnhancedBaselineCard(condition),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.info_outline,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Baseline Recording Guide',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Record baseline values when the person is in a calm, normal state. These values will be used as reference for detecting emotional states.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.sensors_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Waiting for sensor data...',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure your MXChip device is connected and sending data',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSensorCard() {
    final data = _currentSensorData!;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.circle, color: Colors.green, size: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Sensor Data',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  DateFormat('HH:mm:ss').format(DateTime.now()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSensorMetric(
                    Icons.thermostat,
                    'Temperature',
                    '${data.temperature.toStringAsFixed(1)}°C',
                    Colors.orange,
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                Expanded(
                  child: _buildSensorMetric(
                    Icons.water_drop,
                    'Humidity',
                    '${data.humidity.toStringAsFixed(1)}%',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSensorMetric(
                    Icons.accessibility_new,
                    'Motion',
                    data.motion.magnitude.toStringAsFixed(2),
                    Colors.purple,
                  ),
                ),
                Container(width: 1, height: 40, color: Colors.grey[300]),
                Expanded(
                  child: _buildSensorMetric(
                    Icons.volume_up,
                    'Sound',
                    '${data.sound}',
                    Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorMetric(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildEnhancedBaselineCard(String condition) {
    final baseline = _baselines[condition];
    final hasBaseline = baseline != null && !baseline.isEmpty;
    final conditionName = condition[0].toUpperCase() + condition.substring(1);
    
    IconData icon;
    Color cardColor;
    
    switch (condition) {
      case 'anxiety':
        icon = Icons.mood_bad;
        cardColor = Colors.orange;
        break;
      case 'stress':
        icon = Icons.warning;
        cardColor = Colors.red;
        break;
      case 'discomfort':
        icon = Icons.sick;
        cardColor = Colors.amber;
        break;
      default:
        icon = Icons.help;
        cardColor = Colors.grey;
    }

    return Card(
      elevation: hasBaseline ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasBaseline ? cardColor.withOpacity(0.3) : Colors.grey[300]!,
          width: hasBaseline ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: cardColor, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conditionName,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasBaseline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasBaseline ? Icons.check_circle : Icons.circle_outlined,
                                  size: 14,
                                  color: hasBaseline ? Colors.green : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasBaseline ? 'Recorded' : 'Not Set',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: hasBaseline ? Colors.green : Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Baseline Values Comparison
            if (hasBaseline && _currentSensorData != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Baseline vs Current',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              _buildComparisonRow(
                'Temperature',
                '${(baseline.sensorValues['temperature'] ?? 0.0).toStringAsFixed(1)}°C',
                '${_currentSensorData!.temperature.toStringAsFixed(1)}°C',
              ),
              _buildComparisonRow(
                'Humidity',
                '${(baseline.sensorValues['humidity'] ?? 0.0).toStringAsFixed(1)}%',
                '${_currentSensorData!.humidity.toStringAsFixed(1)}%',
              ),
              _buildComparisonRow(
                'Motion',
                (baseline.sensorValues['motion_magnitude'] ?? 0.0).toStringAsFixed(2),
                _currentSensorData!.motion.magnitude.toStringAsFixed(2),
              ),
              const SizedBox(height: 8),
              Text(
                'Recorded: ${DateFormat('MMM dd, yyyy HH:mm').format(baseline.recordedAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
            const SizedBox(height: 16),
            // Action Button - Duration-based recording
            _buildRecordingButton(condition, cardColor, hasBaseline),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(String label, String baselineValue, String currentValue) {
    final baselineNum = double.tryParse(baselineValue.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final currentNum = double.tryParse(currentValue.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
    final difference = (currentNum - baselineNum).abs();
    final isDifferent = difference > 0.1;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  baselineValue,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                Text(
                  'Baseline',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[400],
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            isDifferent ? Icons.arrow_forward : Icons.check,
            size: 16,
            color: isDifferent ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentValue,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDifferent ? Colors.orange : Colors.green,
                      ),
                ),
                Text(
                  'Current',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[400],
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

