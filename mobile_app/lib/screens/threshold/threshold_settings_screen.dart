import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/threshold_service.dart';
import '../../models/user_model.dart';
import '../../models/threshold_model.dart';
import '../../utils/constants.dart';

class ThresholdSettingsScreen extends StatefulWidget {
  const ThresholdSettingsScreen({super.key});

  @override
  State<ThresholdSettingsScreen> createState() =>
      _ThresholdSettingsScreenState();
}

class _ThresholdSettingsScreenState extends State<ThresholdSettingsScreen> {
  UserModel?       _currentUser;
  ThresholdModel?  _current;
  bool             _isLoading  = true;
  bool             _isSaving   = false;

  // Text controllers for each field
  final _tempMinCtrl    = TextEditingController();
  final _tempMaxCtrl    = TextEditingController();
  final _humMinCtrl     = TextEditingController();
  final _humMaxCtrl     = TextEditingController();
  final _motionMaxCtrl  = TextEditingController();
  final _soundMaxCtrl   = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _tempMinCtrl.dispose();
    _tempMaxCtrl.dispose();
    _humMinCtrl.dispose();
    _humMaxCtrl.dispose();
    _motionMaxCtrl.dispose();
    _soundMaxCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final authService      = Provider.of<AuthService>(context, listen: false);
      final thresholdService = Provider.of<ThresholdService>(context, listen: false);
      final user             = await authService.getCurrentUserModel();
      if (!mounted) return;

      setState(() => _currentUser = user);

      if (user != null) {
        final deviceId = user.assignedDeviceId ?? AppConstants.defaultDeviceId;
        final t        = await thresholdService.getThresholds(
          userId:   user.uid,
          deviceId: deviceId,
        );
        _populateControllers(t);
        setState(() => _current = t);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateControllers(ThresholdModel t) {
    _tempMinCtrl.text   = t.tempMin.toStringAsFixed(1);
    _tempMaxCtrl.text   = t.tempMax.toStringAsFixed(1);
    _humMinCtrl.text    = t.humidityMin.toStringAsFixed(1);
    _humMaxCtrl.text    = t.humidityMax.toStringAsFixed(1);
    _motionMaxCtrl.text = t.motionMax.toStringAsFixed(1);
    _soundMaxCtrl.text  = t.soundMax.toStringAsFixed(0);
  }

  void _resetToDefaults() {
    if (_currentUser == null) return;
    final defaults = ThresholdModel.defaults(
      userId:   _currentUser!.uid,
      deviceId: _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId,
    );
    _populateControllers(defaults);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to recommended defaults')),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentUser == null) return;

    setState(() => _isSaving = true);
    try {
      final thresholdService = Provider.of<ThresholdService>(context, listen: false);
      final deviceId = _currentUser!.assignedDeviceId ?? AppConstants.defaultDeviceId;

      final updated = ThresholdModel(
        userId:       _currentUser!.uid,
        deviceId:     deviceId,
        tempMin:      double.parse(_tempMinCtrl.text),
        tempMax:      double.parse(_tempMaxCtrl.text),
        humidityMin:  double.parse(_humMinCtrl.text),
        humidityMax:  double.parse(_humMaxCtrl.text),
        motionMax:    double.parse(_motionMaxCtrl.text),
        soundMax:     double.parse(_soundMaxCtrl.text),
        updatedAt:    DateTime.now(),
      );

      await thresholdService.saveThresholds(updated);
      setState(() => _current = updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:         Text('Thresholds saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:         Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comfort Thresholds'),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _resetToDefaults,
            child: const Text('Defaults'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildInfoCard(),
              const SizedBox(height: 24),
              _buildSensorSection(
                title:    'Temperature',
                icon:     Icons.thermostat,
                color:    Colors.red,
                guidance: 'Recommended: 18 – 26 °C\n'
                           'Below 18°C may cause cold discomfort. '
                           'Above 26°C may cause heat stress, '
                           'particularly for elderly or non-verbal individuals.',
                fields: [
                  _buildField(
                    controller: _tempMinCtrl,
                    label:      'Minimum (°C)',
                    hint:       'e.g. 18.0',
                    min:        0,
                    max:        40,
                  ),
                  _buildField(
                    controller: _tempMaxCtrl,
                    label:      'Maximum (°C)',
                    hint:       'e.g. 26.0',
                    min:        0,
                    max:        50,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSensorSection(
                title:    'Humidity',
                icon:     Icons.water_drop,
                color:    Colors.blue,
                guidance: 'Recommended: 30 – 60 %\n'
                           'Below 30% feels dry and may irritate airways. '
                           'Above 60% feels muggy and can worsen respiratory conditions.',
                fields: [
                  _buildField(
                    controller: _humMinCtrl,
                    label:      'Minimum (%)',
                    hint:       'e.g. 30.0',
                    min:        0,
                    max:        100,
                  ),
                  _buildField(
                    controller: _humMaxCtrl,
                    label:      'Maximum (%)',
                    hint:       'e.g. 60.0',
                    min:        0,
                    max:        100,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSensorSection(
                title:    'Motion',
                icon:     Icons.accessibility_new,
                color:    Colors.purple,
                guidance: 'Recommended max: 2.0 m/s²\n'
                           'Values above this suggest restlessness or agitation. '
                           'Normal calm activity stays below 1.5 m/s².',
                fields: [
                  _buildField(
                    controller: _motionMaxCtrl,
                    label:      'Maximum (m/s²)',
                    hint:       'e.g. 2.0',
                    min:        0,
                    max:        20,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSensorSection(
                title:    'Sound',
                icon:     Icons.volume_up,
                color:    Colors.green,
                guidance: 'Recommended max: 40 units\n'
                           'This is a relative calibrated scale, not decibels. '
                           'Values above 40 indicate a noticeably loud or '
                           'potentially distressing environment.',
                fields: [
                  _buildField(
                    controller: _soundMaxCtrl,
                    label:      'Maximum (units)',
                    hint:       'e.g. 40',
                    min:        0,
                    max:        200,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width:  20,
                        child:  CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Save Thresholds',
                        style: TextStyle(
                          fontSize:    16,
                          fontWeight:  FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Setting Comfort Ranges',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Set the range within which the person wearing the device '
                  'is comfortable. The system will alert you when any reading '
                  'leaves this range. Guidance values are shown for each sensor '
                  'if you are unsure what to enter.',
                  style: TextStyle(
                    fontSize: 13,
                    color:    Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorSection({
    required String            title,
    required IconData          icon,
    required Color             color,
    required String            guidance,
    required List<Widget>      fields,
  }) {
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:        color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize:   18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guidance,
                      style: TextStyle(
                        fontSize: 12,
                        color:    Colors.grey[700],
                        height:   1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...fields,
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String                label,
    required String                hint,
    required double                min,
    required double                max,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller:  controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText:   label,
          hintText:    hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14,
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Required';
          final parsed = double.tryParse(value);
          if (parsed == null) return 'Enter a valid number';
          if (parsed < min || parsed > max) {
            return 'Must be between $min and $max';
          }
          return null;
        },
      ),
    );
  }
}