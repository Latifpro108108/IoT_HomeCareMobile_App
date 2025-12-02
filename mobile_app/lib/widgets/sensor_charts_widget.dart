import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/sensor_data_model.dart';

/// Beautiful charts with bar charts and informative pie charts
class SensorChartsWidget extends StatefulWidget {
  final List<SensorDataModel> sensorDataHistory;

  const SensorChartsWidget({
    super.key,
    required this.sensorDataHistory,
  });

  @override
  State<SensorChartsWidget> createState() => _SensorChartsWidgetState();
}

class _SensorChartsWidgetState extends State<SensorChartsWidget> {
  int _selectedChartType = 0; // 0 = Bar, 1 = Pie

  /// Extracts the number of decimal places from a format function
  int _extractDecimalPlaces(String Function(double) format) {
    // Test with a value that has many decimal places
    const testValue = 1.23456789;
    final formatted = format(testValue);

    // Check if there's a decimal point
    final dotIndex = formatted.indexOf('.');
    if (dotIndex == -1) return 0;

    // Count decimal places (excluding trailing zeros if any)
    final decimalPart = formatted.substring(dotIndex + 1);
    // Remove any non-digit characters (like unit symbols)
    final digitsOnly = decimalPart.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sensorDataHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No data yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Sort by time - CRITICAL
    final sorted = List<SensorDataModel>.from(widget.sensorDataHistory)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Take last 15 for display (optimal for bar chart visibility)
    final data =
        sorted.length > 15 ? sorted.sublist(sorted.length - 15) : sorted;

    return Column(
      children: [
        // Chart type selector
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildChartTypeButton('Line Charts', 0),
              ),
              Expanded(
                child: _buildChartTypeButton('Pie Charts', 1),
              ),
            ],
          ),
        ),

        // Charts
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _selectedChartType == 0
                ? _buildBarCharts(data)
                : _buildPieCharts(data),
          ),
        ),
      ],
    );
  }

  Widget _buildChartTypeButton(String label, int index) {
    final isSelected = _selectedChartType == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedChartType = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildBarCharts(List<SensorDataModel> data) {
    return Column(
      children: [
        _buildLineChart(
          'Temperature',
          Icons.thermostat,
          Colors.red,
          '°C',
          data,
          (d) => d.temperature,
          (v) => v.toStringAsFixed(1),
        ),
        const SizedBox(height: 16),
        _buildLineChart(
          'Humidity',
          Icons.water_drop,
          Colors.blue,
          '%',
          data,
          (d) => d.humidity,
          (v) => v.toStringAsFixed(1),
        ),
        const SizedBox(height: 16),
        _buildLineChart(
          'Motion',
          Icons.accessibility_new,
          Colors.purple,
          'm/s²',
          data,
          (d) => d.motion.magnitude,
          (v) => v.toStringAsFixed(2),
        ),
        const SizedBox(height: 16),
        _buildLineChart(
          'Sound',
          Icons.volume_up,
          Colors.green,
          '',
          data,
          (d) => d.sound.toDouble(),
          (v) => v.toStringAsFixed(0),
        ),
      ],
    );
  }

  Widget _buildLineChart(
    String title,
    IconData icon,
    Color color,
    String unit,
    List<SensorDataModel> data,
    double Function(SensorDataModel) getValue,
    String Function(double) format,
  ) {
    final values = data.map(getValue).toList();
    final timestamps = data.map((d) => d.timestamp).toList();
    final current = values.last;
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final avgVal = values.reduce((a, b) => a + b) / values.length;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.02),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Avg: ${format(avgVal)}$unit',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color, color.withOpacity(0.8)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${format(current)}$unit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Line chart showing trend over time
              SizedBox(
                height: 250,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      painter: CleanLineChartPainter(
                        values: values,
                        timestamps: timestamps,
                        minVal: minVal,
                        maxVal: maxVal,
                        color: color,
                        unit: unit,
                        format: _extractDecimalPlaces(format),
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatLabel(
                      'Min', format(minVal), unit, Colors.grey[700]!),
                  _buildStatLabel(
                      'Max', format(maxVal), unit, Colors.grey[700]!),
                  _buildStatLabel(
                      'Range', format(maxVal - minVal), unit, color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieCharts(List<SensorDataModel> data) {
    return Column(
      children: [
        _buildPieChartCard(
          'Temperature Distribution',
          Icons.thermostat,
          Colors.red,
          '°C',
          data,
          (d) => d.temperature,
          (v) => v.toStringAsFixed(1),
        ),
        const SizedBox(height: 16),
        _buildPieChartCard(
          'Humidity Distribution',
          Icons.water_drop,
          Colors.blue,
          '%',
          data,
          (d) => d.humidity,
          (v) => v.toStringAsFixed(1),
        ),
        const SizedBox(height: 16),
        _buildPieChartCard(
          'Motion Distribution',
          Icons.accessibility_new,
          Colors.purple,
          'm/s²',
          data,
          (d) => d.motion.magnitude,
          (v) => v.toStringAsFixed(2),
        ),
        const SizedBox(height: 16),
        _buildPieChartCard(
          'Sound Distribution',
          Icons.volume_up,
          Colors.green,
          '',
          data,
          (d) => d.sound.toDouble(),
          (v) => v.toStringAsFixed(0),
        ),
      ],
    );
  }

  Widget _buildPieChartCard(
    String title,
    IconData icon,
    Color color,
    String unit,
    List<SensorDataModel> data,
    double Function(SensorDataModel) getValue,
    String Function(double) format,
  ) {
    final values = data.map(getValue).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;
    final avgVal = values.reduce((a, b) => a + b) / values.length;

    // Use meaningful thresholds based on average
    // Low: below average - 15% of range
    // High: above average + 15% of range
    // Normal: everything in between
    final lowThreshold = avgVal - (range * 0.15);
    final highThreshold = avgVal + (range * 0.15);

    final low = values.where((v) => v < lowThreshold).length;
    final normal =
        values.where((v) => v >= lowThreshold && v <= highThreshold).length;
    final high = values.where((v) => v > highThreshold).length;

    final total = values.length;
    final lowPercent = total > 0 ? low / total : 0.0;
    final normalPercent = total > 0 ? normal / total : 0.0;
    final highPercent = total > 0 ? high / total : 0.0;

    // Format meaningful range labels
    String lowLabel, normalLabel, highLabel;
    if (title.contains('Temperature')) {
      lowLabel = 'Below ${format(lowThreshold)}$unit';
      normalLabel =
          '${format(lowThreshold)}$unit - ${format(highThreshold)}$unit';
      highLabel = 'Above ${format(highThreshold)}$unit';
    } else if (title.contains('Humidity')) {
      lowLabel = 'Dry (< ${format(lowThreshold)}$unit)';
      normalLabel =
          'Normal (${format(lowThreshold)}$unit - ${format(highThreshold)}$unit)';
      highLabel = 'Humid (> ${format(highThreshold)}$unit)';
    } else if (title.contains('Motion')) {
      lowLabel = 'Low (< ${format(lowThreshold)}$unit)';
      normalLabel =
          'Normal (${format(lowThreshold)}$unit - ${format(highThreshold)}$unit)';
      highLabel = 'High (> ${format(highThreshold)}$unit)';
    } else {
      lowLabel = 'Low (< ${format(lowThreshold)}$unit)';
      normalLabel =
          'Normal (${format(lowThreshold)}$unit - ${format(highThreshold)}$unit)';
      highLabel = 'High (> ${format(highThreshold)}$unit)';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.1),
              color.withOpacity(0.02),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          'Avg: ${format(avgVal)}$unit',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Pie chart with labels
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(160, 160),
                          painter: _PieChartPainter(
                            lowPercent: lowPercent,
                            midPercent: normalPercent,
                            highPercent: highPercent,
                            color: color,
                          ),
                        ),
                        // Center text showing total
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$total',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            Text(
                              'readings',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildPieLegend(
                          lowLabel,
                          lowPercent,
                          color.withOpacity(0.6),
                          low,
                          color,
                        ),
                        const SizedBox(height: 12),
                        _buildPieLegend(
                          normalLabel,
                          normalPercent,
                          color,
                          normal,
                          color,
                        ),
                        const SizedBox(height: 12),
                        _buildPieLegend(
                          highLabel,
                          highPercent,
                          color.withOpacity(0.8),
                          high,
                          color,
                        ),
                      ],
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

  Widget _buildPieLegend(
    String label,
    double percent,
    Color color,
    int count,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count (${(percent * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatLabel(String label, String value, String unit, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value$unit',
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class LineChart extends StatelessWidget {
  final List<double> values;
  final List<DateTime> timestamps;
  final double minVal;
  final double maxVal;
  final Color color;
  final String unit;
  final int format;

  const LineChart({
    super.key,
    required this.values,
    required this.timestamps,
    required this.minVal,
    required this.maxVal,
    required this.color,
    required this.unit,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: CleanLineChartPainter(
        values: values,
        timestamps: timestamps,
        minVal: minVal,
        maxVal: maxVal,
        color: color,
        unit: unit,
        format: format,
      ),
      size: const Size(double.infinity, 240),
    );
  }
}

class CleanLineChartPainter extends CustomPainter {
  final List<double> values;
  final List<DateTime> timestamps;
  final double minVal;
  final double maxVal;
  final Color color;
  final String unit;
  final int format;

  CleanLineChartPainter({
    required this.values,
    required this.timestamps,
    required this.minVal,
    required this.maxVal,
    required this.color,
    required this.unit,
    required this.format,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || timestamps.isEmpty) return;

    // Optimized paddings for better centering and space usage
    const double leftPadding = 36; // Reduced for better space usage
    const double rightPadding = 12;
    const double topPadding = 16;
    const double bottomPadding = 28;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    final range = (maxVal - minVal).abs() < 1e-6 ? 1 : maxVal - minVal;
    double normalize(double v) => (v - minVal) / range;

    // Grid
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.15)
      ..strokeWidth = 0.7;

    final textPainter = TextPainter(
      textAlign: TextAlign.right,
      textDirection: TextDirection.ltr,
    );

    // Y labels and grid (4 lines)
    const gridSteps = 4;
    for (int i = 0; i <= gridSteps; i++) {
      final t = i / gridSteps;
      final y = topPadding + chartHeight * t;
      final value = maxVal - range * t;

      // horizontal line
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );

      // label
      textPainter.text = TextSpan(
        text: '${value.toStringAsFixed(format)}$unit',
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(leftPadding - 8 - textPainter.width, y - textPainter.height / 2),
      );
    }

    // Build data points with intelligent time-based spacing
    final points = <Offset>[];
    final n = values.length;

    if (n == 0) return;

    // Calculate time range
    final timeRange =
        timestamps.last.difference(timestamps.first).inMilliseconds;

    // Use time-based spacing if there's meaningful time spread (at least 1 second)
    // Otherwise use even spacing to avoid bunching
    final useTimeBasedSpacing = timeRange >= 1000 && n > 1;

    for (int i = 0; i < n; i++) {
      double xFactor;

      if (n == 1) {
        xFactor = 0.5; // Center single point
      } else if (useTimeBasedSpacing) {
        // Time-based: map timestamp to 0..1 range
        final timeOffset =
            timestamps[i].difference(timestamps.first).inMilliseconds;
        xFactor = timeOffset / timeRange;
      } else {
        // Even spacing: distribute evenly across width
        xFactor = i / (n - 1);
      }

      final x = leftPadding + xFactor * chartWidth;
      final y = topPadding + chartHeight * (1 - normalize(values[i]));
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // Smooth path using improved cubic bezier with better control points
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) {
      // single point – short flat segment
      path.lineTo(points.first.dx + 0.01, points.first.dy);
    } else if (points.length == 2) {
      // Two points: simple smooth curve
      final p0 = points[0];
      final p1 = points[1];
      final dx = (p1.dx - p0.dx) * 0.4;
      final dy = (p1.dy - p0.dy) * 0.4;
      path.cubicTo(
        p0.dx + dx,
        p0.dy + dy,
        p1.dx - dx,
        p1.dy - dy,
        p1.dx,
        p1.dy,
      );
    } else {
      // Multiple points: smooth cubic bezier with direction-aware control points
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = points[i];
        final p1 = points[i + 1];

        // Calculate control points based on neighboring points for smoother curves
        Offset cp1, cp2;

        if (i == 0) {
          // First segment: use next point to determine direction
          final p2 = points[i + 2];
          final dx1 = (p1.dx - p0.dx) * 0.4;
          final dy1 = (p1.dy - p0.dy) * 0.4;
          final dx2 = (p2.dx - p0.dx) * 0.2;
          final dy2 = (p2.dy - p0.dy) * 0.2;
          cp1 = Offset(p0.dx + dx1, p0.dy + dy1);
          cp2 = Offset(p1.dx - dx2, p1.dy - dy2);
        } else if (i == points.length - 2) {
          // Last segment: use previous point to determine direction
          final pPrev = points[i - 1];
          final dx1 = (p1.dx - pPrev.dx) * 0.2;
          final dy1 = (p1.dy - pPrev.dy) * 0.2;
          final dx2 = (p1.dx - p0.dx) * 0.4;
          final dy2 = (p1.dy - p0.dy) * 0.4;
          cp1 = Offset(p0.dx + dx1, p0.dy + dy1);
          cp2 = Offset(p1.dx - dx2, p1.dy - dy2);
        } else {
          // Middle segments: use both previous and next points for smooth transitions
          final pPrev = points[i - 1];
          final pNext = points[i + 2];

          // Calculate tangent vectors
          final tangent1 = Offset(
            (p1.dx - pPrev.dx) * 0.3,
            (p1.dy - pPrev.dy) * 0.3,
          );
          final tangent2 = Offset(
            (pNext.dx - p0.dx) * 0.3,
            (pNext.dy - p0.dy) * 0.3,
          );

          cp1 = Offset(p0.dx + tangent1.dx, p0.dy + tangent1.dy);
          cp2 = Offset(p1.dx - tangent2.dx, p1.dy - tangent2.dy);
        }

        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
      }
    }

    // Area fill
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height - bottomPadding)
      ..lineTo(points.first.dx, size.height - bottomPadding)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withOpacity(0.28),
          color.withOpacity(0.04),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Dots
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final p in points) {
      canvas.drawCircle(p, 5.5, outlinePaint);
      canvas.drawCircle(p, 3.5, dotPaint);
    }

    // X labels (start / middle / end)
    if (timestamps.length > 1) {
      final labelStyle = TextStyle(
        color: Colors.grey.shade600,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      );

      final indices = <int>{0, timestamps.length ~/ 2, timestamps.length - 1};
      for (final idx in indices) {
        final ts = timestamps[idx];
        final label = _formatTimeLabel(ts, timestamps.first, timestamps.last);

        textPainter.text = TextSpan(text: label, style: labelStyle);
        textPainter.layout();

        final x = points[idx].dx;
        final y = size.height - bottomPadding + 6;
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, y),
        );
      }
    }
  }

  String _formatTimeLabel(DateTime time, DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration.inDays >= 1 || duration.inHours >= 1) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant CleanLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.timestamps != timestamps ||
        oldDelegate.minVal != minVal ||
        oldDelegate.maxVal != maxVal ||
        oldDelegate.color != color ||
        oldDelegate.unit != unit ||
        oldDelegate.format != format;
  }
}

class _PieChartPainter extends CustomPainter {
  final double lowPercent;
  final double midPercent;
  final double highPercent;
  final Color color;

  _PieChartPainter({
    required this.lowPercent,
    required this.midPercent,
    required this.highPercent,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 15;

    double startAngle = -math.pi / 2; // Start at top

    // Draw low segment
    if (lowPercent > 0) {
      final sweepAngle = lowPercent * 2 * math.pi;
      final paint = Paint()
        ..color = color.withOpacity(0.6)
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }

    // Draw mid segment
    if (midPercent > 0) {
      final sweepAngle = midPercent * 2 * math.pi;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
      startAngle += sweepAngle;
    }

    // Draw high segment
    if (highPercent > 0) {
      final sweepAngle = highPercent * 2 * math.pi;
      final paint = Paint()
        ..color = color.withOpacity(0.8)
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
    }

    // Draw center circle for donut effect
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.5, centerPaint);

    // Draw border around pie
    final borderPaint = Paint()
      ..color = Colors.grey.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(_PieChartPainter old) {
    return old.lowPercent != lowPercent ||
        old.midPercent != midPercent ||
        old.highPercent != highPercent ||
        old.color != color;
  }
}
