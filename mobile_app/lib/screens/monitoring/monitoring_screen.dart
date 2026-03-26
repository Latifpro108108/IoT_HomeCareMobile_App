import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/firebase_service.dart';
import '../../services/fall_detection_service.dart';
import '../../models/user_model.dart';
import '../../models/sensor_data_model.dart';
import '../../models/threshold_model.dart';
import '../../utils/constants.dart';
import '../../widgets/sensor_charts_widget.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen>
    with SingleTickerProviderStateMixin {
  SensorDataModel?              _currentSensorData;
  ThresholdModel?               _thresholds;
  List<SensorDataModel>         _sensorHistory  = [];
  List<Map<String, dynamic>>    _fallHistory    = [];
  late TabController            _tabController;

  StreamSubscription<SensorDataModel?>? _sensorSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.getCurrentUserModel().then((user) {
      if (!mounted) return;
      if (user != null) _setupStreams(user);
    });
  }

  void _setupStreams(UserModel user) {
    final firebaseService  = Provider.of<FirebaseService>(context, listen: false);
    final fallService      = Provider.of<FallDetectionService>(context, listen: false);
    final deviceId         = user.assignedDeviceId ?? AppConstants.defaultDeviceId;

    // Fetch current data and thresholds immediately
    firebaseService.fetchCurrentSensorData(deviceId).then((data) {
      if (mounted && data != null) setState(() => _currentSensorData = data);
    });

    firebaseService.fetchThresholds(
      userId: user.uid, deviceId: deviceId,
    ).then((t) {
      if (mounted) setState(() => _thresholds = t);
    });

    firebaseService.fetchHistoricalSensorData(deviceId, limit: 50).then((history) {
      if (mounted) setState(() => _sensorHistory = history);
    });

    fallService.fetchFallHistory(deviceId: deviceId).then((falls) {
      if (mounted) setState(() => _fallHistory = falls);
    });

    // Real-time sensor stream
    _sensorSubscription = firebaseService
        .getCurrentSensorData(deviceId)
        .listen((data) {
      if (data == null || !mounted) return;
      setState(() {
        _currentSensorData = data;
        final exists = _sensorHistory.any(
          (d) => d.timestamp.millisecondsSinceEpoch ==
                 data.timestamp.millisecondsSinceEpoch,
        );
        if (!exists) {
          final updated = [..._sensorHistory, data];
          updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          if (updated.length > 50) updated.removeAt(0);
          _sensorHistory = updated;
        }
      });
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
            Tab(icon: Icon(Icons.dashboard),   text: 'Live'),
            Tab(icon: Icon(Icons.show_chart),  text: 'Charts'),
            Tab(icon: Icon(Icons.history),     text: 'Falls'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLiveTab(),
          _buildChartsTab(),
          _buildFallHistoryTab(),
        ],
      ),
    );
  }

  // ── Live Tab ──────────────────────────────────────────────────────────────

  Widget _buildLiveTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_currentSensorData != null) ...[
            _buildLiveSensorGrid(),
            const SizedBox(height: 16),
            if (_thresholds != null) _buildThresholdStatusCard(),
            const SizedBox(height: 16),
            _buildDetailedStatsCard(),
          ] else
            _buildNoDataCard(),
        ],
      ),
    );
  }

  Widget _buildLiveSensorGrid() {
    final d = _currentSensorData!;
    final t = _thresholds;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.green, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live Readings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  DateFormat('HH:mm:ss').format(d.timestamp),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildReadingTile(
                    label: 'Temperature',
                    value: '${d.temperature.toStringAsFixed(1)}°C',
                    icon:  Icons.thermostat,
                    color: Colors.red,
                    inRange: t?.tempInRange(d.temperature) ?? true,
                    rangeHint: t != null
                        ? '${t.tempMin.toStringAsFixed(0)}–${t.tempMax.toStringAsFixed(0)}°C'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadingTile(
                    label: 'Humidity',
                    value: '${d.humidity.toStringAsFixed(1)}%',
                    icon:  Icons.water_drop,
                    color: Colors.blue,
                    inRange: t?.humidityInRange(d.humidity) ?? true,
                    rangeHint: t != null
                        ? '${t.humidityMin.toStringAsFixed(0)}–${t.humidityMax.toStringAsFixed(0)}%'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildReadingTile(
                    label: 'Motion',
                    value: '${d.motion.magnitude.toStringAsFixed(2)} m/s²',
                    icon:  Icons.accessibility_new,
                    color: Colors.purple,
                    inRange: t?.motionInRange(d.motion.magnitude) ?? true,
                    rangeHint: t != null
                        ? 'max ${t.motionMax.toStringAsFixed(1)} m/s²'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadingTile(
                    label: 'Sound',
                    value: '${d.sound} units',
                    icon:  Icons.volume_up,
                    color: Colors.green,
                    inRange: t?.soundInRange(d.sound.toDouble()) ?? true,
                    rangeHint: t != null
                        ? 'max ${t.soundMax.toStringAsFixed(0)} units'
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingTile({
    required String   label,
    required String   value,
    required IconData icon,
    required Color    color,
    required bool     inRange,
    String?           rangeHint,
  }) {
    final displayColor = inRange ? color : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        displayColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: displayColor.withOpacity(inRange ? 0.2 : 0.6),
          width: inRange ? 1 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: displayColor, size: 18),
              const Spacer(),
              if (!inRange)
                Icon(Icons.warning_amber, color: Colors.orange, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: displayColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          if (rangeHint != null) ...[
            const SizedBox(height: 4),
            Text(
              rangeHint,
              style: TextStyle(
                fontSize: 10,
                color: inRange ? Colors.grey[400] : Colors.orange[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThresholdStatusCard() {
    final t = _thresholds!;
    final d = _currentSensorData!;

    final allOk = t.tempInRange(d.temperature) &&
                  t.humidityInRange(d.humidity) &&
                  t.motionInRange(d.motion.magnitude) &&
                  t.soundInRange(d.sound.toDouble());

    return Card(
      elevation: 0,
      color: allOk
          ? Colors.green.withOpacity(0.05)
          : Colors.orange.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              allOk ? Icons.check_circle : Icons.warning_amber,
              color: allOk ? Colors.green : Colors.orange,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                allOk
                    ? 'All readings within comfort range'
                    : 'One or more readings outside comfort range',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: allOk ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedStatsCard() {
    if (_sensorHistory.isEmpty) return const SizedBox.shrink();

    final temps    = _sensorHistory.map((d) => d.temperature).toList();
    final hums     = _sensorHistory.map((d) => d.humidity).toList();
    final motions  = _sensorHistory.map((d) => d.motion.magnitude).toList();
    final sounds   = _sensorHistory.map((d) => d.sound.toDouble()).toList();

    double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
    double mx(List<double> l)  => l.reduce((a, b) => a > b ? a : b);

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
                const Text(
                  'Session Statistics',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildStat(
                  'Avg Temp',
                  '${avg(temps).toStringAsFixed(1)}°C',
                  Colors.red,
                )),
                Expanded(child: _buildStat(
                  'Max Temp',
                  '${mx(temps).toStringAsFixed(1)}°C',
                  Colors.red,
                )),
                Expanded(child: _buildStat(
                  'Avg Humidity',
                  '${avg(hums).toStringAsFixed(1)}%',
                  Colors.blue,
                )),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStat(
                  'Avg Motion',
                  avg(motions).toStringAsFixed(2),
                  Colors.purple,
                )),
                Expanded(child: _buildStat(
                  'Peak Motion',
                  mx(motions).toStringAsFixed(2),
                  Colors.purple,
                )),
                Expanded(child: _buildStat(
                  'Peak Sound',
                  mx(sounds).toStringAsFixed(0),
                  Colors.green,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.sensors_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Waiting for sensor data...',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ── Charts Tab ────────────────────────────────────────────────────────────

  Widget _buildChartsTab() {
    return SensorChartsWidget(
      sensorDataHistory: _sensorHistory,
      //thresholds:        _thresholds,
    );
  }

  // ── Fall History Tab ──────────────────────────────────────────────────────

  Widget _buildFallHistoryTab() {
    if (_fallHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green[300]),
            const SizedBox(height: 16),
            const Text(
              'No falls recorded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Fall events will appear here when detected',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _fallHistory.length,
      itemBuilder: (context, index) {
        final event      = _fallHistory[index];
        final confidence = ((event['confidence'] ?? 0.0) * 100).toInt();
        final ts         = (event['timestamp'] ?? 0) as num;
        final time       = DateTime.fromMillisecondsSinceEpoch(
          ts < 10000000000 ? ts.toInt() * 1000 : ts.toInt(),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.red, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fall Detected — $confidence% confidence',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy  HH:mm:ss').format(time),
                        style: TextStyle(
                          fontSize: 12,
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
      },
    );
  }
}