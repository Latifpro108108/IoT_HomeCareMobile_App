import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../models/user_model.dart';
import '../../models/sensor_data_model.dart';
import '../../models/emotional_state_model.dart';
import '../../utils/constants.dart';
import '../../widgets/sensor_charts_widget.dart';
import 'package:intl/intl.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with SingleTickerProviderStateMixin {
  UserModel? _currentUser;
  SensorDataModel? _currentSensorData;
  EmotionalStateResult? _currentEmotionalState;
  List<EmotionalStateResult> _emotionalStateHistory = [];
  List<SensorDataModel> _sensorDataHistory = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load immediately without blocking
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.getCurrentUserModel().then((user) {
      if (mounted) {
        setState(() => _currentUser = user);
        if (user != null) {
          _setupStreams();
        }
      }
    });
  }

  void _setupStreams() {
    if (_currentUser == null) return;

    final firebaseService =
        Provider.of<FirebaseService>(context, listen: false);
    final deviceId =
        _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;

    // Get current data immediately
    firebaseService.fetchCurrentSensorData(deviceId).then((data) {
      if (mounted && data != null) {
        setState(() {
          _currentSensorData = data;
          _sensorDataHistory = [data];
        });
      }
    });

    // Real-time sensor stream - SIMPLE
    firebaseService.getCurrentSensorData(deviceId).listen((data) {
      if (mounted && data != null) {
        setState(() {
          _currentSensorData = data;

          // Add to history if new
          final exists = _sensorDataHistory.any((d) =>
              d.timestamp.millisecondsSinceEpoch ==
              data.timestamp.millisecondsSinceEpoch);

          if (!exists) {
            final updated = List<SensorDataModel>.from(_sensorDataHistory)
              ..add(data);
            updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            if (updated.length > 50) updated.removeAt(0);
            _sensorDataHistory = updated;
          }
        });
      }
    });

    // Emotional state
    firebaseService.getCurrentEmotionalState(_currentUser!.uid).listen((state) {
      if (mounted) {
        setState(() => _currentEmotionalState = state);
      }
    });

    firebaseService
        .fetchEmotionalStateHistory(_currentUser!.uid, limit: 10)
        .then((history) {
      if (mounted) {
        setState(() => _emotionalStateHistory = history);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.show_chart), text: 'Charts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboard(),
          _buildCharts(),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with device info
          if (_currentUser != null) ...[
            _buildDeviceInfoCard(),
            const SizedBox(height: 16),
          ],

          // Current emotional state
          if (_currentEmotionalState != null) ...[
            _buildEmotionalCard(),
            const SizedBox(height: 16),
          ],

          // Current sensor readings with more details
          if (_currentSensorData != null) ...[
            _buildSensorCard(),
            const SizedBox(height: 16),
            _buildDetailedStatsCard(),
            const SizedBox(height: 16),
          ],

          // Data summary card
          if (_sensorDataHistory.isNotEmpty) ...[
            _buildDataSummaryCard(),
            const SizedBox(height: 16),
          ],

          // Emotional state history
          if (_emotionalStateHistory.isNotEmpty) ...[
            Text(
              'Emotional State History',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            ..._emotionalStateHistory.map((s) => _buildHistoryItem(s)),
          ],
        ],
      ),
    );
  }

  Widget _buildCharts() {
    return SensorChartsWidget(
      sensorDataHistory: _sensorDataHistory,
    );
  }

  Widget _buildDeviceInfoCard() {
    final deviceId = _currentUser?.assignedDeviceId ?? 'Not assigned';
    final lastUpdate = _currentSensorData?.timestamp;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withOpacity(0.1),
              Colors.purple.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.devices, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device ID',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      deviceId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (lastUpdate != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last update: ${_formatTimeAgo(lastUpdate)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.check_circle,
                color: _currentSensorData != null ? Colors.green : Colors.grey,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmotionalCard() {
    final s = _currentEmotionalState!;
    Color c;
    IconData i;
    String description;

    switch (s.state) {
      case EmotionalState.anxiety:
        c = Colors.orange;
        i = Icons.mood_bad;
        description = 'Elevated stress indicators detected';
        break;
      case EmotionalState.stress:
        c = Colors.red;
        i = Icons.warning;
        description = 'High stress levels detected';
        break;
      case EmotionalState.discomfort:
        c = Colors.amber;
        i = Icons.sick;
        description = 'Mild discomfort detected';
        break;
      case EmotionalState.normal:
        c = Colors.green;
        i = Icons.check_circle;
        description = 'All readings within normal range';
        break;
      default:
        c = Colors.grey;
        i = Icons.help;
        description = 'Status unknown';
        break;
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              c.withOpacity(0.15),
              c.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(i, size: 32, color: c),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Status',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.state.displayName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: c,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${(s.confidence * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Detected: ${DateFormat('MMM dd, HH:mm:ss').format(s.detectedAt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSensorCard() {
    final d = _currentSensorData!;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.withOpacity(0.05),
              Colors.purple.withOpacity(0.02),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sensors, color: Colors.blue[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Current Sensor Readings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildMetric(
                      'Temperature',
                      Icons.thermostat,
                      '${d.temperature.toStringAsFixed(1)}°C',
                      Colors.red,
                      _getTempStatus(d.temperature),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetric(
                      'Humidity',
                      Icons.water_drop,
                      '${d.humidity.toStringAsFixed(1)}%',
                      Colors.blue,
                      _getHumidityStatus(d.humidity),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetric(
                      'Motion',
                      Icons.accessibility_new,
                      '${d.motion.magnitude.toStringAsFixed(2)} m/s²',
                      Colors.purple,
                      _getMotionStatus(d.motion.magnitude),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetric(
                      'Sound',
                      Icons.volume_up,
                      '${d.sound}',
                      Colors.green,
                      _getSoundStatus(d.sound),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedStatsCard() {
    if (_sensorDataHistory.isEmpty) return const SizedBox.shrink();

    final sorted = List<SensorDataModel>.from(_sensorDataHistory)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final temps = sorted.map((d) => d.temperature).toList();
    final humidities = sorted.map((d) => d.humidity).toList();
    final motions = sorted.map((d) => d.motion.magnitude).toList();
    final sounds = sorted.map((d) => d.sound.toDouble()).toList();

    final tempAvg = temps.reduce((a, b) => a + b) / temps.length;
    final humidityAvg = humidities.reduce((a, b) => a + b) / humidities.length;
    final motionAvg = motions.reduce((a, b) => a + b) / motions.length;
    final soundAvg = sounds.reduce((a, b) => a + b) / sounds.length;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Average Values',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Temp Avg',
                      '${tempAvg.toStringAsFixed(1)}°C', Colors.red),
                ),
                Expanded(
                  child: _buildStatItem('Humidity Avg',
                      '${humidityAvg.toStringAsFixed(1)}%', Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Motion Avg',
                      '${motionAvg.toStringAsFixed(2)}', Colors.purple),
                ),
                Expanded(
                  child: _buildStatItem('Sound Avg',
                      '${soundAvg.toStringAsFixed(0)}', Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSummaryCard() {
    final dataCount = _sensorDataHistory.length;
    final firstData = _sensorDataHistory.isNotEmpty
        ? _sensorDataHistory.first.timestamp
        : null;
    final lastData = _currentSensorData?.timestamp;

    Duration? duration;
    if (firstData != null && lastData != null) {
      duration = lastData.difference(firstData);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.withOpacity(0.1),
              Colors.teal.withOpacity(0.05),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.data_usage, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Points Collected',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$dataCount readings',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (duration != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Span: ${_formatDuration(duration)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
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
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    String label,
    IconData icon,
    String value,
    Color color,
    String status,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _getTempStatus(double temp) {
    if (temp < 18) return 'Cold';
    if (temp > 25) return 'Warm';
    return 'Normal';
  }

  String _getHumidityStatus(double humidity) {
    if (humidity < 30) return 'Dry';
    if (humidity > 70) return 'Humid';
    return 'Comfortable';
  }

  String _getMotionStatus(double motion) {
    if (motion < 0.5) return 'Still';
    if (motion > 2.0) return 'Active';
    return 'Moderate';
  }

  String _getSoundStatus(int sound) {
    if (sound < 30) return 'Quiet';
    if (sound > 60) return 'Loud';
    return 'Normal';
  }

  String _formatTimeAgo(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }

  Widget _buildHistoryItem(EmotionalStateResult s) {
    Color c = s.state == EmotionalState.anxiety
        ? Colors.orange
        : s.state == EmotionalState.stress
            ? Colors.red
            : s.state == EmotionalState.discomfort
                ? Colors.amber
                : s.state == EmotionalState.normal
                    ? Colors.green
                    : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: c.withOpacity(0.2),
            child: Icon(Icons.circle, color: c, size: 12)),
        title: Text(s.state.displayName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(DateFormat('HH:mm:ss').format(s.detectedAt)),
        trailing: Text('${(s.confidence * 100).toInt()}%',
            style: TextStyle(color: c, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
